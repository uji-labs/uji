local M = {}

local MAX_ERROR_BODY = 2000
local EVENTS = { nulls = false }

M.idle = 120

function M.clip(text, max)
    local count, cut = 0, nil
    for start in text:gmatch("()[^\128-\191]") do
        count = count + 1
        if count == max + 1 then
            cut = start
        end
    end
    if count <= max then
        return text
    end
    return string.format("%s\n… [truncated, %d of %d chars shown]", text:sub(1, cut - 1), max, count)
end

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function provider(message)
    return { kind = "provider", message = message }
end

function M.truncated_stream()
    return { kind = "http", message = "the provider closed the stream before the reply finished" }
end

function M.output_limit()
    return provider("response hit the model's output limit and was cut off")
end

function M.empty_response()
    return provider("empty response")
end

local function truncated_call(name)
    return provider(
        "the reply was cut off while calling `" .. name .. "`, so its arguments are incomplete - raise "
            .. "the model's max output"
    )
end

local function status_error(response)
    local status = response.status
    if status == 401 or status == 403 then
        return { kind = "auth", status = status }
    end
    local wait = response.headers["retry-after"]
    return {
        kind = "http",
        status = status,
        retry_after = wait and tonumber(wait:match("^%s*(%d+)%s*$")),
        message = M.clip(trim(response.body), MAX_ERROR_BODY),
    }
end

local function incomplete(arguments)
    if arguments:match("^%s*$") then
        return false
    end
    return not pcall(uji.json.decode, arguments)
end

local Parts = {}
Parts.__index = Parts

local function parts(reply)
    return setmetatable({
        reply = reply,
        text = {},
        reasoning = {},
        usage = { input = 0, output = 0, cache_read = 0, cache_write = 0 },
        hit_limit = false,
        complete = false,
        calls = {},
        moved = false,
    }, Parts)
end

function Parts:push_text(delta)
    self.text[#self.text + 1] = delta
    self.reply.text(delta)
    self.moved = true
end

function Parts:push_reasoning(delta)
    self.reasoning[#self.reasoning + 1] = delta
    self.reply.reasoning(delta)
    self.moved = true
end

function Parts:finish(reason)
    if reason then
        self.finish_reason = reason
    end
    self.complete = true
    self.moved = true
end

function Parts:call(index)
    self.moved = true
    for _, call in ipairs(self.calls) do
        if call.index == index then
            return call
        end
    end
    local call = { index = index, id = "", name = "", arguments = "" }
    self.calls[#self.calls + 1] = call
    return call
end

function Parts:progress()
    local moved = self.moved
    self.moved = false
    return moved
end

function Parts:has_text()
    return table.concat(self.text) ~= ""
end

function Parts:tool_calls()
    table.sort(self.calls, function(a, b)
        return a.index < b.index
    end)
    local calls = {}
    for _, call in ipairs(self.calls) do
        if incomplete(call.arguments) then
            return nil, truncated_call(call.name)
        end
        calls[#calls + 1] = { id = call.id, name = call.name, arguments = call.arguments }
    end
    return calls
end

function Parts:answer(calls)
    local usage = self.usage
    local total = usage.input + usage.output + usage.cache_read + usage.cache_write
    local reasoning = table.concat(self.reasoning)
    return {
        text = table.concat(self.text),
        reasoning = reasoning ~= "" and reasoning or nil,
        tool_calls = calls,
        usage = total > 0 and usage or nil,
    }
end

local function finished(parts)
    if not parts.complete then
        return M.truncated_stream()
    end
end

local function settle(parts, calls)
    if #calls == 0 and parts.hit_limit then
        return M.output_limit()
    end
end

local function progressed(line, state, read)
    local data = line:match("^data: (.*)$")
    if not data then
        return false
    end
    if data == "[DONE]" then
        state:finish()
    else
        local ok, event = pcall(uji.json.decode, data, EVENTS)
        if ok and type(event) == "table" then
            pcall(read, event, state)
        end
    end
    return state:progress()
end

local function drain(body, state, read)
    local idle = M.idle
    local deadline = uji.os.clock() + idle
    while true do
        local line, err = body:line(math.max(deadline - uji.os.clock(), 0))
        if line == false then
            return { kind = "http", message = "no data arrived for " .. idle .. " seconds" }
        end
        if not line then
            return err and { kind = "http", message = err }
        end
        if progressed(line, state, read) then
            deadline = uji.os.clock() + idle
        end
    end
end

local function run(spec, reply)
    local state = parts(reply)
    local headers = { ["Content-Type"] = "application/json" }
    for name, value in pairs(spec.headers) do
        headers[name] = value
    end
    local body, err = uji.net.open({
        url = spec.url,
        method = "POST",
        headers = headers,
        body = uji.json.encode(spec.body),
    })
    if not body then
        return nil, { kind = "http", message = err }
    end
    if body.status < 200 or body.status >= 300 then
        return nil, status_error({ status = body.status, headers = body.headers, body = body:read() or "" })
    end
    local failure = drain(body, state, spec.read)
    if failure then
        return nil, failure
    end
    local problem = (spec.finished or finished)(state)
    if problem then
        return nil, problem
    end
    local calls, cut = state:tool_calls()
    if not calls then
        return nil, cut
    end
    problem = (spec.settle or settle)(state, calls)
    if problem then
        return nil, problem
    end
    return state:answer(calls)
end

function M.run(spec, reply)
    local answer, failure = run(spec, reply)
    if answer then
        reply.done(answer)
        return answer
    end
    reply.fail(failure)
    return nil, failure
end

return M
