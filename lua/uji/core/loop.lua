local class = require("uji.core.class")
local executor = require("uji.core.executor")
local json = require("uji.utils.json")
local list = require("uji.utils.list")
local model = require("uji.core.model")
local sys = require("uji.sys")
local text = require("ito").text
local tool = require("uji.core.tool")
local view = require("uji.core.agent.view")

local RETRY_ATTEMPTS = 5
local RETRY_INITIAL = 2
local RETRY_FACTOR = 2
local RETRY_JITTER = 0.25
local RETRY_CEILING = 30
local MAX_RETRY_AFTER = 60
local REASON_WIDTH = 160
local RETRYABLE = { [408] = true, [409] = true, [425] = true, [429] = true }
local ARRAY = getmetatable(sys.json.array({}))

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
        local hint = "authentication rejected (" .. failure.status .. ") - check the api key for this provider"
        return failure.message and hint .. ": " .. failure.message or hint
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
    if value == sys.json.null then
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
    local value, problem = json.object(raw)
    if not value then
        return nil,
            string.format(
                "error: arguments are not valid JSON (%s). Send a single JSON object matching the tool schema, "
                    .. "with no markdown fences. Received: %s",
                tostring(problem),
                text.clip(raw, 500)
            )
    end
    if type(value) == "table" and getmetatable(value) ~= ARRAY then
        return value
    end
    return nil, "error: arguments must be a JSON object, got " .. kind(value) .. ". Send a single object matching the tool schema."
end

local function fresh_id()
    return string.format("call_%08x%08x", math.random(0, 0xffffffff), math.random(0, 0xffffffff))
end

local Loop = class()

function Loop:init(agent, turn)
    self.agent = agent
    for key, value in pairs(turn) do
        self[key] = value
    end
    self.names, self.known = {}, {}
    for _, spec in ipairs(self.tools) do
        self.names[#self.names + 1] = spec.name
        self.known[spec.name] = true
    end
end

function Loop:call()
    local agent = self.agent
    return model.stream({
        model = self.model,
        system = self.system,
        messages = self.messages,
        tools = self.tools,
        effort = self.effort,
        reasoning = self.reasoning,
        max_output = self.max_output,
        cache = self.cache,
    }, {
        text = function(delta)
            agent:delta("text", delta)
        end,
        reasoning = function(delta)
            agent:delta("reasoning", delta)
        end,
    })
end

function Loop:generate()
    local attempt = 0
    while true do
        local answer, failure = self:call()
        if answer then
            return answer
        end
        if attempt >= RETRY_ATTEMPTS or not retryable(failure) then
            self.agent:failed(describe(failure))
            return nil
        end
        local wait = failure.retry_after and math.min(failure.retry_after, MAX_RETRY_AFTER) or backoff(attempt)
        attempt = attempt + 1
        local reason = text.clip(describe(failure):match("[^\n]*"), REASON_WIDTH)
        self.agent:restarted(attempt, RETRY_ATTEMPTS, math.floor(wait), reason)
        sys.sleep(wait)
    end
end

function Loop:compact()
    local agent = self.agent
    if agent.skipped_compaction or not agent:needs_compaction() then
        return
    end
    if agent:fold(agent:keep_recent_now()) then
        self.messages = view.build(agent.session:entries())
    end
end

function Loop:steer()
    local message = self.agent:steer()
    if not message then
        return false
    end
    self.messages[#self.messages + 1] = message
    return true
end

function Loop:refused(call, status, reason)
    self.agent:tool_completed(call, { text = reason })
    return { resolved = { status = status, reason = reason } }
end

function Loop:prepare(call)
    if not self.known[call.name] then
        return self:refused(
            call,
            "failed",
            string.format("error: unknown tool `%s`. Available tools: %s.", call.name, table.concat(self.names, ", "))
        )
    end
    local args, problem = arguments(call.arguments)
    if not args then
        return self:refused(call, "failed", problem)
    end
    args, problem = self.agent:resolve(call.name, args)
    if not args then
        return self:refused(call, "failed", problem)
    end
    local decision = self.agent:approve(call.name, args)
    if decision.deny then
        return self:refused(call, "denied", "denied: " .. decision.deny)
    end
    local agent = self.agent
    return {
        run = function()
            agent:tool_running(call)
            return agent:tool_completed(call, agent:run_tool(call, decision.arguments))
        end,
    }
end

function Loop:execution(calls)
    for _, call in ipairs(calls) do
        if tool.execution(call.name) == executor.Sequential then
            return executor.Sequential
        end
    end
    return executor.Parallel
end

function Loop:result(call, result)
    local value
    if result.status == "completed" then
        value = result.value
    else
        value = { text = result.reason }
    end
    if type(value) ~= "table" then
        value = { text = tostring(value) }
    end
    value.text = self.agent:after_tool(call.name, value.text or "")
    self.agent:tool_result(call, value)
    self.messages[#self.messages + 1] = {
        type = "tool",
        tool_call_id = call.id,
        name = call.name,
        content = value.text,
        images = value.images,
    }
end

function Loop:run_tools(calls)
    local Execution = self:execution(calls)
    local items = list.mapped(calls, function(call)
        if Execution == executor.Parallel then
            return self:prepare(call)
        end
        return {
            run = function()
                local item = self:prepare(call)
                local result = item.resolved
                if not result then
                    result = { status = "completed", value = item.run() }
                end
                self:result(call, result)
            end,
        }
    end)
    self.batch = Execution(items)
    self.batch:execute()
    local results = self.batch:await()
    local turn = self.agent.turn
    for index, call in ipairs(calls) do
        if not (turn and turn.answered[call.id]) then
            self:result(call, results[index])
        end
    end
    self.batch = nil
end

function Loop:interrupt()
    if self.batch then
        self.batch:cancel("interrupted by the user")
    end
end

function Loop:run()
    while true do
        self:compact()
        self:steer()
        local answer = self:generate()
        if not answer then
            return
        end
        if answer.usage then
            self.agent:usage(answer.usage)
        end
        local calls = answer.tool_calls or {}
        local taken = {}
        for _, call in ipairs(calls) do
            if call.id:match("^%s*$") or taken[call.id] then
                call.id = fresh_id()
            end
            while taken[call.id] do
                call.id = fresh_id()
            end
            taken[call.id] = true
        end
        local message = {
            type = "assistant",
            text = answer.text or "",
            tool_calls = calls,
            reasoning = answer.reasoning,
            replay = answer.replay,
            usage = answer.usage,
        }
        if #calls == 0 then
            if not self.agent:queued() then
                return self.agent:done(message)
            end
            self.agent:assistant_step(message)
            self.messages[#self.messages + 1] = message
            self:steer()
        else
            self.agent:assistant_step(message)
            self.messages[#self.messages + 1] = message
            self:run_tools(calls)
        end
    end
end

return Loop
