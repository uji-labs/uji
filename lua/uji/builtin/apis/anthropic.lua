local common = require("uji.builtin.apis.common")
local stream = require("uji.builtin.apis.stream")

local VERSION = "2023-06-01"
local MAX_TOKENS = "max_tokens"
local TTL = { long = "1h" }
local BINDING = "thinking-binding-controls-2026-08-01"
local EFFORT = { minimal = "low", low = "low", medium = "medium", high = "high", xhigh = "xhigh", max = "max" }
local RETRIED = { overloaded_error = 529, api_error = 500, rate_limit_error = 429 }

local Anthropic = uji.class()

function Anthropic:init(opts)
    for key, value in pairs(opts or {}) do
        self[key] = value
    end
end

local function text(value)
    return { type = "text", text = value }
end

local function version(model)
    local numbers = {}
    for part in model:gmatch("%d+") do
        if #part > 2 then
            break
        end
        numbers[#numbers + 1] = tonumber(part)
    end
    if #numbers == 0 then
        return math.huge
    end
    return numbers[1] + (numbers[2] or 0) / 10
end

local function family(model)
    return model:match("^claude%-(%a+)")
end

function Anthropic:adaptive(model)
    return version(model) >= 4.6
end

function Anthropic:always_thinks(model)
    local name = family(model)
    return name == "fable" or name == "mythos" or version(model) >= 5.5
end

function Anthropic:binds(model)
    local name = family(model)
    local at = version(model)
    return ((name == "fable" or name == "mythos") and at >= 5.1) or at >= 5.5
end

function Anthropic:efforts(model)
    if not self:adaptive(model) then
        return { "off", "minimal", "low", "medium", "high" }
    end
    if version(model) < 4.7 then
        return { "off", "low", "medium", "high", "max" }
    end
    if self:always_thinks(model) then
        return { "low", "medium", "high", "xhigh", "max" }
    end
    return { "off", "low", "medium", "high", "xhigh", "max" }
end

function Anthropic:picture(image)
    return { type = "image", source = { type = "base64", media_type = image.media_type, data = image.data } }
end

function Anthropic:tool_use(call)
    return { type = "tool_use", id = call.id, name = call.name, input = common.arguments(call.arguments) }
end

function Anthropic:user(item)
    return {
        role = "user",
        content = common.parts(item.images, function(image)
            return self:picture(image)
        end, item.text, text),
    }
end

local function kept(item, request)
    local replay = item.replay
    return replay and replay.api == "anthropic" and replay.model == request.model and replay
end

function Anthropic:replayed(item, replay)
    local calls, next_call = item.tool_calls or {}, 1
    local blocks = uji.json.array({})
    for _, block in ipairs(replay.content) do
        if block.type == "thinking" then
            blocks[#blocks + 1] = { type = "thinking", thinking = block.thinking, signature = block.signature }
        elseif block.type == "redacted_thinking" then
            blocks[#blocks + 1] = { type = "redacted_thinking", data = block.data }
        elseif block.type == "text" and block.text ~= "" then
            blocks[#blocks + 1] = text(block.text)
        elseif block.type == "tool_use" and calls[next_call] then
            blocks[#blocks + 1] = self:tool_use(calls[next_call])
            next_call = next_call + 1
        end
    end
    for index = next_call, #calls do
        blocks[#blocks + 1] = self:tool_use(calls[index])
    end
    return blocks
end

function Anthropic:assistant(item, request)
    local replay = kept(item, request)
    if replay then
        return { role = "assistant", content = self:replayed(item, replay) }
    end
    local blocks = common.map(item.tool_calls, function(call)
        return self:tool_use(call)
    end)
    if item.text ~= "" then
        table.insert(blocks, 1, text(item.text))
    end
    return { role = "assistant", content = blocks }
end

function Anthropic:tool(item)
    local content = item.content
    if item.images then
        content = common.parts(item.images, function(image)
            return self:picture(image)
        end, item.content, text)
    end
    return {
        role = "user",
        content = { { type = "tool_result", tool_use_id = item.tool_call_id, content = content } },
    }
end

function Anthropic:spec(tool)
    return { name = tool.name, description = tool.description, input_schema = tool.parameters }
end

local function cache(body, retention)
    if retention == "off" then
        return
    end
    local control = { type = "ephemeral", ttl = TTL[retention] }
    local function mark(block)
        if block then
            block.cache_control = control
        end
    end
    mark(body.system[#body.system])
    mark(body.tools and body.tools[#body.tools])
    for at = #body.messages, 1, -1 do
        local message = body.messages[at]
        if message.role == "user" then
            mark(message.content[#message.content])
            return
        end
    end
end

function Anthropic:thinking(body, request)
    local effort = request.effort
    if not self:adaptive(request.model) then
        local _, budget = common.fit_thinking(effort, request.max_output)
        body.thinking = budget > 0 and { type = "enabled", budget_tokens = budget } or nil
        return
    end
    if effort == "off" then
        body.thinking = { type = "disabled" }
        return
    end
    body.thinking = { type = "adaptive", display = "summarized" }
    if self:binds(request.model) then
        body.thinking.block_binding = { prefix_mismatch_behavior = "drop_block" }
    end
    body.output_config = effort and { effort = EFFORT[effort] } or nil
end

function Anthropic:messages(request)
    local shapes = {
        user = function(item)
            return self:user(item, request)
        end,
        assistant = function(item)
            return self:assistant(item, request)
        end,
        tool = function(item)
            return self:tool(item, request)
        end,
    }
    return common.translate(request.messages, shapes)
end

function Anthropic:body(request)
    local system = common.system(request)
    local out = {
        model = request.model,
        max_tokens = math.max(request.max_output, common.MIN_ANSWER),
        system = system ~= "" and { text(system) } or uji.json.array({}),
        messages = self:messages(request),
        stream = true,
        tools = common.nonempty(common.map(request.tools, function(tool)
            return self:spec(tool)
        end)),
    }
    if request.reasoning then
        self:thinking(out, request)
    end
    cache(out, request.cache)
    local identity = request.auth.oauth and request.auth.oauth.identity_prompt
    if identity and not (out.system[1] and out.system[1].text == identity) then
        table.insert(out.system, 1, text(identity))
    end
    return out
end

function Anthropic:headers(request, body)
    local auth = request.auth
    local out = { ["anthropic-version"] = VERSION }
    local betas = {}
    if auth.oauth then
        out.Authorization = common.bearer(auth.oauth.token)
        for name, value in pairs(auth.oauth.headers or {}) do
            out[name] = value
        end
    elseif auth.key then
        out["x-api-key"] = auth.key
    end
    if out["anthropic-beta"] then
        betas[#betas + 1] = out["anthropic-beta"]
    end
    if body.thinking and body.thinking.block_binding then
        betas[#betas + 1] = BINDING
    end
    out["anthropic-beta"] = #betas > 0 and table.concat(betas, ",") or nil
    return out
end

local function block_delta(event, kind)
    if event.type == "content_block_delta" and event.delta and event.delta.type == kind then
        return event.delta
    end
end

local function open_block(parts, event)
    local block = event.content_block
    if not (block and event.index) then
        return
    end
    parts.blocks = parts.blocks or {}
    if block.type == "thinking" then
        parts.blocks[event.index] = { type = "thinking", thinking = "", signature = block.signature or "" }
    elseif block.type == "redacted_thinking" then
        parts.blocks[event.index] = { type = "redacted_thinking", data = block.data }
    elseif block.type == "text" then
        parts.blocks[event.index] = { type = "text", text = "" }
    elseif block.type == "tool_use" then
        parts.blocks[event.index] = { type = "tool_use" }
    end
end

local function block(parts, event)
    return parts.blocks and event.index and parts.blocks[event.index]
end

local function failed(reported)
    reported = type(reported) == "table" and reported or {}
    local kind = type(reported.type) == "string" and reported.type or "error"
    local message = kind .. ": " .. (type(reported.message) == "string" and reported.message or "the provider reported an error")
    local status = RETRIED[kind]
    if status then
        return { kind = "http", status = status, message = message }
    end
    return { kind = "provider", message = message }
end

function Anthropic:read(event, parts)
    if event.type == "error" then
        parts.failure = parts.failure or failed(event.error)
        return
    end
    if event.type == "content_block_start" then
        open_block(parts, event)
    end
    local thinking = block_delta(event, "thinking_delta")
    if thinking and thinking.thinking then
        parts:push_reasoning(thinking.thinking)
        local open = block(parts, event)
        if open then
            open.thinking = open.thinking .. thinking.thinking
        end
    end
    local signed = block_delta(event, "signature_delta")
    local open = block(parts, event)
    if signed and open then
        open.signature = signed.signature
    end
    local reply = block_delta(event, "text_delta")
    if reply and reply.text then
        parts:push_text(reply.text)
        if open and open.type == "text" then
            open.text = open.text .. reply.text
        end
    end
    local input = event.message and event.message.usage
    if input then
        parts.usage = {
            input = input.input_tokens or 0,
            output = parts.usage.output,
            cache_read = input.cache_read_input_tokens or 0,
            cache_write = input.cache_creation_input_tokens or 0,
        }
    end
    if event.usage then
        parts.usage.output = event.usage.output_tokens or 0
    end
    if event.delta and event.delta.stop_reason == MAX_TOKENS then
        parts.hit_limit = true
    end
    if event.type == "message_stop" then
        parts:finish()
    end
    if not event.index then
        return
    end
    local started = event.content_block
    if event.type == "content_block_start" and started and started.type == "tool_use" then
        local entry = parts:call(event.index)
        entry.id = started.id or ""
        entry.name = started.name or ""
    end
    local fragment = block_delta(event, "input_json_delta")
    if fragment and fragment.partial_json then
        local entry = parts:call(event.index)
        entry.arguments = entry.arguments .. fragment.partial_json
    end
end

local function signed(kept_block)
    return kept_block.type == "redacted_thinking" or (kept_block.type == "thinking" and kept_block.signature ~= "")
end

function Anthropic:keep(parts, request)
    local indexes, thought = {}, false
    for index, kept_block in pairs(parts.blocks or {}) do
        if kept_block.type ~= "thinking" or signed(kept_block) then
            indexes[#indexes + 1] = index
        end
        thought = thought or signed(kept_block)
    end
    if not thought then
        return
    end
    table.sort(indexes)
    local content = {}
    for _, index in ipairs(indexes) do
        content[#content + 1] = parts.blocks[index]
    end
    parts.replay = { api = "anthropic", model = request.model, content = content }
end

function Anthropic:stream(request, reply)
    local body = self:body(request)
    return stream.run({
        url = request.provider.base_url .. "/messages",
        headers = self:headers(request, body),
        body = body,
        read = function(event, parts)
            self:read(event, parts)
        end,
        settle = function(parts)
            self:keep(parts, request)
        end,
    }, reply)
end

return Anthropic
