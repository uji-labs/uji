local common = require("uji.builtin.apis.common")
local stream = require("uji.builtin.apis.stream")

local REASONING = { "reasoning_content", "reasoning", "reasoning_text" }
local BRIDGE = "The tool calls returned images, which follow."

local OpenAI = uji.class()

OpenAI.max_tokens_field = "max_tokens"
OpenAI.finish_reason = true
OpenAI.cache_key = false
OpenAI.tool_result_name = false
OpenAI.bridge_tool_images = false

function OpenAI:init(opts)
    for key, value in pairs(opts or {}) do
        self[key] = value
    end
end

function OpenAI:url(request)
    return request.provider.base_url .. "/chat/completions"
end

function OpenAI:headers(request)
    return { Authorization = common.bearer(request.auth.key) }
end

function OpenAI:thinking(body, request)
    if request.effort and request.effort ~= "off" then
        body.reasoning_effort = request.effort
    end
end

function OpenAI:picture(image)
    return { type = "image_url", image_url = { url = "data:" .. image.media_type .. ";base64," .. image.data } }
end

local function written(text)
    return { type = "text", text = text }
end

function OpenAI:user(item)
    if not item.images then
        return { role = "user", content = item.text }
    end
    return {
        role = "user",
        content = common.parts(item.images, function(image)
            return self:picture(image)
        end, item.text, written),
    }
end

function OpenAI:call(tool_call)
    return {
        id = tool_call.id,
        type = "function",
        ["function"] = {
            name = tool_call.name,
            arguments = uji.json.encode(common.arguments(tool_call.arguments)),
        },
    }
end

function OpenAI:assistant(item)
    return {
        role = "assistant",
        content = item.text ~= "" and item.text or uji.json.null,
        tool_calls = common.nonempty(common.map(item.tool_calls, function(tool_call)
            return self:call(tool_call)
        end)),
    }
end

function OpenAI:tool(item)
    return {
        role = "tool",
        content = item.content,
        tool_call_id = item.tool_call_id,
        name = self.tool_result_name and item.name or nil,
    }
end

function OpenAI:show(images)
    local shown = {
        {
            role = "user",
            content = common.parts(images, function(image)
                return self:picture(image)
            end, common.SHOWN, written),
        },
    }
    if self.bridge_tool_images then
        table.insert(shown, 1, { role = "assistant", content = BRIDGE })
    end
    return shown
end

function OpenAI:messages(request)
    local shapes = {
        user = function(item)
            return self:user(item, request)
        end,
        system = function(item)
            return { role = "system", content = item.text }
        end,
        assistant = function(item)
            return self:assistant(item, request)
        end,
        tool = function(item)
            return self:tool(item, request)
        end,
    }
    local messages = common.translate(request.messages, shapes, function(images)
        return self:show(images)
    end)
    if request.system then
        table.insert(messages, 1, { role = "system", content = request.system })
    end
    return messages
end

function OpenAI:spec(tool)
    return {
        type = "function",
        ["function"] = { name = tool.name, description = tool.description, parameters = tool.parameters },
    }
end

function OpenAI:body(request)
    local out = {
        model = request.model,
        messages = self:messages(request),
        tools = common.nonempty(common.map(request.tools, function(tool)
            return self:spec(tool)
        end)),
        stream = true,
        stream_options = { include_usage = true },
        prompt_cache_key = self.cache_key and request.session or nil,
    }
    if request.reasoning then
        self:thinking(out, request)
    end
    if self.max_tokens_field then
        out[self.max_tokens_field] = math.max(request.max_output, common.MIN_ANSWER)
    end
    return out
end

function OpenAI:usage(reported)
    local details = reported.prompt_tokens_details or {}
    local cache_read =
        math.max(details.cached_tokens or 0, reported.prompt_cache_hit_tokens or 0, reported.cached_tokens or 0)
    local cache_write = details.cache_write_tokens or 0
    return {
        input = math.max((reported.prompt_tokens or 0) - cache_read - cache_write, 0),
        output = reported.completion_tokens or 0,
        cache_read = cache_read,
        cache_write = cache_write,
    }
end

function OpenAI:reasoning(delta)
    for _, field in ipairs(REASONING) do
        if type(delta[field]) == "string" then
            return delta[field]
        end
    end
end

function OpenAI:read(event, parts)
    local choice = event.choices and event.choices[1]
    local delta = choice and choice.delta or {}
    local reasoning = self:reasoning(delta)
    if reasoning then
        parts:push_reasoning(reasoning)
    end
    if delta.content then
        parts:push_text(delta.content)
    end
    if choice and choice.finish_reason then
        parts.hit_limit = choice.finish_reason == "length"
        parts:finish()
    end
    if event.usage then
        parts.usage = self:usage(event.usage)
    end
    for _, piece in ipairs(delta.tool_calls or {}) do
        local entry = parts:call(piece.index or 0)
        if piece.id then
            entry.id = piece.id
        end
        local fn = piece["function"]
        if fn and fn.name then
            entry.name = fn.name
        end
        if fn and fn.arguments then
            entry.arguments = entry.arguments .. fn.arguments
        end
    end
end

function OpenAI:finished(parts)
    if not self.finish_reason then
        parts:finish()
    end
end

function OpenAI:settle(parts, calls)
    if #calls == 0 and not parts:has_text() then
        return { kind = "provider", message = "empty response" }
    end
end

function OpenAI:stream(request, reply)
    return stream.run({
        url = self:url(request),
        headers = self:headers(request),
        body = self:body(request),
        read = function(event, parts)
            self:read(event, parts)
        end,
        finished = function(parts)
            return self:finished(parts)
        end,
        settle = function(parts, calls)
            return self:settle(parts, calls)
        end,
    }, reply)
end

return OpenAI
