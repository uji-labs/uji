local stream = require("uji.wires.stream")

local MAX_ITERATIONS = 100
local RETRY_ATTEMPTS = 5
local RETRY_INITIAL = 2
local RETRY_FACTOR = 2
local RETRY_JITTER = 0.25
local RETRY_CEILING = 30
local MAX_RETRY_AFTER = 60
local APPROVAL_TIMEOUT = 300
local RETRYABLE = { [408] = true, [409] = true, [425] = true, [429] = true }
local ARRAY = getmetatable(uji.json.array({}))
local CANCELLED = {}
local TIMED_OUT = {}

local function retryable(failure)
    if type(failure) ~= "table" or failure.kind ~= "http" then
        return false
    end
    local status = failure.status
    return status == nil or RETRYABLE[status] == true or (status >= 500 and status < 600)
end

local function describe(failure)
    if type(failure) ~= "table" then
        return tostring(failure)
    end
    if failure.kind == "auth" then
        return "authentication rejected (" .. failure.status .. ") - check the api key for this provider"
    end
    if failure.kind == "provider" then
        return "provider: " .. failure.message
    end
    return "http: " .. (failure.status and failure.status .. ": " or "") .. failure.message
end

local function backoff(attempt)
    local step = math.min(RETRY_INITIAL * RETRY_FACTOR ^ attempt, RETRY_CEILING)
    return step * math.max(1 + RETRY_JITTER * (math.random() * 2 - 1), 0)
end

local function kind(value)
    if value == uji.json.null then
        return "null"
    end
    local name = type(value)
    if name == "boolean" then
        return "a boolean"
    elseif name == "number" then
        return "a number"
    elseif name == "string" then
        return "a string"
    elseif getmetatable(value) == ARRAY then
        return "an array"
    end
    return "an object"
end

local function arguments(raw)
    local trimmed = raw:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return {}
    end
    local ok, value = pcall(uji.json.decode, trimmed)
    if not ok then
        return nil,
            string.format(
                "error: arguments are not valid JSON (%s). Send a single JSON object matching the tool schema, "
                    .. "with no markdown fences. Received: %s",
                tostring(value),
                stream.clip(trimmed, 500)
            )
    end
    if type(value) == "table" and getmetatable(value) ~= ARRAY then
        return value
    end
    return nil,
        "error: arguments must be a JSON object, got " .. kind(value) .. ". Send a single object matching the tool schema."
end

local function fresh_id()
    return string.format("call_%08x%08x", math.random(0, 0xffffffff), math.random(0, 0xffffffff))
end

local Turn = {}
Turn.__index = Turn

function Turn:resume(...)
    if coroutine.status(self.thread) ~= "suspended" then
        return
    end
    local ok, err = coroutine.resume(self.thread, ...)
    if not ok then
        self:report({ type = "failed", message = "agent loop: " .. tostring(err) })
    end
end

function Turn:await(start)
    if self.cancelled then
        return CANCELLED
    end
    local pending = {}
    local function settle(...)
        if pending.settled then
            return
        end
        pending.settled = true
        self.pending = nil
        if pending.stop then
            pending.stop()
        end
        if pending.waiting then
            self:resume(...)
        else
            pending.early = table.pack(...)
        end
    end
    self.pending = settle
    pending.stop = start(settle)
    if pending.settled then
        if pending.stop then
            pending.stop()
        end
        return table.unpack(pending.early, 1, pending.early.n)
    end
    pending.waiting = true
    return coroutine.yield()
end

function Turn:cancel()
    if self.cancelled then
        return
    end
    self.cancelled = true
    if self.pending then
        self.pending(CANCELLED)
    end
end

function Turn:report(event, on_applied)
    self.host.report(event, on_applied)
end

function Turn:call()
    local route, err = self:await(self.host.route)
    if route == CANCELLED then
        return CANCELLED
    end
    if not route then
        return nil, err
    end
    local request = {
        model = self.model,
        system = self.system,
        messages = self.messages,
        tools = self.tools,
        effort = self.effort,
        max_output = self.max_output,
        cache = self.cache,
        session = self.session,
        provider = route.provider,
        auth = route.auth,
    }
    return self:await(function(done)
        return self.host.stream(route.wire, request, {
            text = function(delta)
                self:report({ type = "text", text = delta })
            end,
            reasoning = function(delta)
                self:report({ type = "reasoning", text = delta })
            end,
            done = function(answer)
                done(answer)
            end,
            fail = function(failure)
                done(nil, failure)
            end,
        })
    end)
end

function Turn:generate()
    local attempt = 0
    while true do
        local answer, failure = self:call()
        if answer == CANCELLED then
            return nil
        end
        if answer then
            return answer
        end
        if attempt >= RETRY_ATTEMPTS or not retryable(failure) then
            self:report({ type = "failed", message = describe(failure) })
            return nil
        end
        local wait = failure.retry_after and math.min(failure.retry_after, MAX_RETRY_AFTER) or backoff(attempt)
        attempt = attempt + 1
        self:report({ type = "restarted", attempt = attempt, of = RETRY_ATTEMPTS, wait = math.floor(wait) })
        local slept = self:await(function(done)
            return uji.defer(wait, done)
        end)
        if slept == CANCELLED then
            return nil
        end
    end
end

function Turn:compact()
    local folded = self:await(function(done)
        return self.host.compact(self.messages, done)
    end)
    if folded == CANCELLED then
        return CANCELLED
    end
    if folded then
        self.messages = folded.messages
        self:report({ type = "compacted", usage = folded.usage, count = folded.count })
    end
end

function Turn:steer()
    local text = self:await(self.host.steer)
    if text == CANCELLED or text == nil then
        return false
    end
    self.messages[#self.messages + 1] = { type = "user", text = text }
    return true
end

function Turn:execute(call)
    if not self.known[call.name] then
        return string.format(
            "error: unknown tool `%s`. Available tools: %s.",
            call.name,
            table.concat(self.names, ", ")
        )
    end
    local args, problem = arguments(call.arguments)
    if not args then
        return problem
    end
    local decision = self:await(function(done)
        local stop_approval = self.host.approve({ name = call.name, arguments = args }, done)
        local stop_timer = uji.defer(APPROVAL_TIMEOUT, function()
            done(TIMED_OUT)
        end)
        return function()
            stop_approval()
            stop_timer()
        end
    end)
    if decision == CANCELLED then
        return CANCELLED
    end
    if decision == TIMED_OUT then
        return "denied: timed out waiting for confirmation"
    end
    if decision.deny then
        return "denied: " .. decision.deny
    end
    return self:await(function(done)
        return self.host.run_tool(call.name, decision.arguments, done)
    end)
end

function Turn:run_tools(calls)
    for _, call in ipairs(calls) do
        local content
        if self.cancelled then
            content = "error: interrupted by the user before this tool ran"
        else
            content = self:execute(call)
            if content == CANCELLED then
                content = "error: interrupted by the user while this tool ran"
            end
        end
        content = self.host.after_tool(call.name, content)
        self:report({ type = "tool_result", tool_call_id = call.id, name = call.name, content = content })
        self.messages[#self.messages + 1] = { type = "tool", tool_call_id = call.id, name = call.name, content = content }
    end
end

function Turn:run()
    for _ = 1, MAX_ITERATIONS do
        if self.cancelled or self:compact() == CANCELLED then
            return self:report({ type = "cancelled" })
        end
        self:steer()
        local answer = self:generate()
        if not answer then
            if self.cancelled then
                self:report({ type = "cancelled" })
            end
            return
        end
        local usage = answer.usage
        if usage then
            self:report({
                type = "usage",
                input = usage.input,
                output = usage.output,
                cache_read = usage.cache_read,
                cache_write = usage.cache_write,
            })
        end
        local calls = answer.tool_calls or {}
        for _, call in ipairs(calls) do
            if call.id:match("^%s*$") then
                call.id = fresh_id()
            end
        end
        local text, reasoning = answer.text, answer.reasoning
        if #calls == 0 then
            if not self:steer() then
                return self:report({ type = "done", text = text, reasoning = reasoning })
            end
            self:report({ type = "assistant_step", text = text, tool_calls = {}, reasoning = reasoning })
            self.messages[#self.messages + 1] = { type = "assistant", text = text, reasoning = reasoning }
        else
            local step = { type = "assistant_step", text = text, tool_calls = calls, reasoning = reasoning }
            self:await(function(done)
                self:report(step, done)
            end)
            self.messages[#self.messages + 1] =
                { type = "assistant", text = text, tool_calls = calls, reasoning = reasoning }
            self:run_tools(calls)
            if self.cancelled then
                return self:report({ type = "cancelled" })
            end
        end
    end
    self:report({
        type = "failed",
        message = "stopped after " .. MAX_ITERATIONS .. " tool iterations without a final answer",
    })
end

local M = {}

function M.start(turn, host)
    local self = setmetatable(turn, Turn)
    self.host = host
    self.names, self.known = {}, {}
    for _, tool in ipairs(self.tools) do
        self.names[#self.names + 1] = tool.name
        self.known[tool.name] = true
    end
    self.thread = coroutine.create(function()
        self:run()
    end)
    self:resume()
    return function()
        self:cancel()
    end
end

return M
