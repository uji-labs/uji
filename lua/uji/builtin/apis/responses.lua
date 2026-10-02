local common = require("uji.builtin.apis.common")
local stream = require("uji.builtin.apis.stream")

local MIN_OUTPUT = 16

local Responses = uji.class()

Responses.cache_key = true

function Responses:init(opts)
    for key, value in pairs(opts or {}) do
        self[key] = value
    end
end

function Responses:efforts()
    return { "low", "medium", "high" }
end

function Responses:url(request)
    return request.provider.base_url .. "/responses"
end

function Responses:headers(request)
    return { Authorization = common.bearer(request.auth.key) }
end

function Responses:reasoning(request)
    if request.effort == "off" then
        return { effort = "none" }
    end
    return { effort = request.effort, summary = "auto" }
end

function Responses:picture(image)
    return { type = "input_image", image_url = "data:" .. image.media_type .. ";base64," .. image.data }
end

local function said(text)
    return { type = "input_text", text = text }
end

function Responses:user(item)
    return {
        role = "user",
        content = common.parts(item.images, function(image)
            return self:picture(image)
        end, item.text, said),
    }
end

function Responses:call(tool_call, id)
    return {
        type = "function_call",
        id = id,
        call_id = tool_call.id,
        name = tool_call.name,
        arguments = uji.json.encode(common.arguments(tool_call.arguments)),
    }
end

local function message(text, id)
    return {
        type = "message",
        role = "assistant",
        id = id,
        status = "completed",
        content = { { type = "output_text", text = text, annotations = uji.json.array({}) } },
    }
end

local function kept(item, request)
    local replay = item.replay
    return replay and replay.api == "responses" and replay.model == request.model and replay
end

function Responses:assistant(item, request)
    local calls, next_call, out = item.tool_calls or {}, 1, {}
    local replay = kept(item, request)
    local wrote = false
    for _, entry in ipairs(replay and replay.items or {}) do
        if entry.kind == "reasoning" then
            out[#out + 1] = entry.item
        elseif entry.kind == "message" and not wrote and item.text ~= "" then
            out[#out + 1] = message(item.text, entry.id)
            wrote = true
        elseif entry.kind == "function_call" and calls[next_call] then
            out[#out + 1] = self:call(calls[next_call], entry.id)
            next_call = next_call + 1
        end
    end
    if not wrote and item.text ~= "" then
        table.insert(out, 1, { role = "assistant", content = item.text })
    end
    for index = next_call, #calls do
        out[#out + 1] = self:call(calls[index])
    end
    return out
end

function Responses:tool(item)
    return { type = "function_call_output", call_id = item.tool_call_id, output = item.content }
end

function Responses:show(images)
    return {
        role = "user",
        content = common.parts(images, function(image)
            return self:picture(image)
        end, common.SHOWN, said),
    }
end

function Responses:input(request)
    local out, pending = uji.json.array({}), {}
    local system = common.system(request)
    if system ~= "" then
        out[1] = { role = "system", content = system }
    end
    local function flush()
        if #pending > 0 then
            out[#out + 1] = self:show(pending)
            pending = {}
        end
    end
    for _, item in ipairs(request.messages) do
        if item.type ~= "tool" then
            flush()
        end
        if item.type == "user" then
            out[#out + 1] = self:user(item, request)
        elseif item.type == "assistant" then
            for _, entry in ipairs(self:assistant(item, request)) do
                out[#out + 1] = entry
            end
        elseif item.type == "tool" then
            out[#out + 1] = self:tool(item, request)
            for _, image in ipairs(item.images or {}) do
                pending[#pending + 1] = image
            end
        end
    end
    flush()
    return out
end

function Responses:spec(tool)
    return { type = "function", name = tool.name, description = tool.description, parameters = tool.parameters }
end

function Responses:body(request)
    local out = {
        model = request.model,
        input = self:input(request),
        tools = common.nonempty(common.map(request.tools, function(tool)
            return self:spec(tool)
        end)),
        stream = true,
        store = false,
        prompt_cache_key = self.cache_key and request.session or nil,
        max_output_tokens = math.max(request.max_output, MIN_OUTPUT),
    }
    if request.reasoning then
        out.reasoning = self:reasoning(request)
        if request.effort ~= "off" then
            out.include = { "reasoning.encrypted_content" }
        end
    end
    return out
end

function Responses:usage(reported)
    local details = reported.input_tokens_details or {}
    local cached = details.cached_tokens or 0
    return {
        input = math.max((reported.input_tokens or 0) - cached, 0),
        output = reported.output_tokens or 0,
        cache_read = cached,
        cache_write = 0,
    }
end

function Responses:record(event, parts)
    local item = event.item or {}
    parts.items = parts.items or {}
    if item.type == "reasoning" then
        parts.items[#parts.items + 1] = { kind = "reasoning", item = item }
        parts.reasoned = true
    elseif item.type == "message" then
        parts.items[#parts.items + 1] = { kind = "message", id = item.id }
    elseif item.type == "function_call" then
        parts.items[#parts.items + 1] = { kind = "function_call", id = item.id }
        if item.arguments then
            parts:call(event.output_index or 0).arguments = item.arguments
        end
    end
end

function Responses:read(event, parts)
    local kind = event.type
    if kind == "response.output_item.added" and event.item and event.item.type == "function_call" then
        local entry = parts:call(event.output_index or 0)
        entry.id = event.item.call_id or ""
        entry.name = event.item.name or ""
        entry.arguments = event.item.arguments or ""
    elseif kind == "response.function_call_arguments.delta" then
        local entry = parts:call(event.output_index or 0)
        entry.arguments = entry.arguments .. (event.delta or "")
    elseif kind == "response.output_text.delta" then
        parts:push_text(event.delta or "")
    elseif kind == "response.reasoning_summary_text.delta" or kind == "response.reasoning_text.delta" then
        parts:push_reasoning(event.delta or "")
    elseif kind == "response.reasoning_summary_part.added" and (event.summary_index or 0) > 0 then
        parts:push_reasoning("\n\n")
    elseif kind == "response.output_item.done" then
        self:record(event, parts)
    elseif kind == "response.completed" or kind == "response.incomplete" then
        local response = event.response or {}
        if response.usage then
            parts.usage = self:usage(response.usage)
        end
        local details = response.incomplete_details
        parts.hit_limit = details ~= nil and details.reason == "max_output_tokens"
        parts:finish()
    elseif kind == "response.failed" then
        local failed = event.response and event.response.error or {}
        parts.failure = { kind = "provider", message = failed.message or "the response failed" }
    elseif kind == "error" then
        parts.failure = { kind = "provider", message = event.message or "the provider reported an error" }
    end
end

function Responses:keep(parts, request)
    if parts.reasoned then
        parts.replay = { api = "responses", model = request.model, items = parts.items }
    end
end

function Responses:settle(parts, calls)
    if #calls == 0 and not parts:has_text() then
        return { kind = "provider", message = "empty response" }
    end
end

function Responses:stream(request, reply)
    return stream.run({
        url = self:url(request),
        headers = self:headers(request),
        body = self:body(request),
        read = function(event, parts)
            self:read(event, parts)
        end,
        settle = function(parts, calls)
            self:keep(parts, request)
            return self:settle(parts, calls)
        end,
    }, reply)
end

return Responses
