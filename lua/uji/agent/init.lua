local class = require("uji.class")
local compactor = require("uji.agent.compactor")
local context = require("uji.context")
local event = require("uji.event")
local model = require("uji.model")
local notices = require("uji.notices")
local process = require("uji.system.process")
local sys = require("uji.sys")
local task = require("uji.task")
local title = require("uji.agent.title")
local tool = require("uji.tool")
local view = require("uji.agent.view")

local APPROVAL_TIMEOUT = 300
local KEEP_CEILING_FRACTION = 4
local SHELL_OUTPUT = 64 * 1024
local STOPPED = "error: uji stopped before this tool returned a result"
local WHILE_RUNNING = "error: interrupted by the user while this tool ran"
local BEFORE_RUNNING = "error: interrupted by the user before this tool ran"

local function listing(arguments)
    local keys = {}
    for key in pairs(arguments) do
        keys[#keys + 1] = key
    end
    if #keys == 0 then
        return sys.json.encode(arguments)
    end
    table.sort(keys)
    local lines = {}
    for index, key in ipairs(keys) do
        local value = arguments[key]
        lines[index] = key .. ": " .. (type(value) == "string" and value or sys.json.encode(value))
    end
    return table.concat(lines, "\n")
end

local function decision_of(answer)
    if type(answer) ~= "table" then
        return nil
    end
    if type(answer.deny) == "string" then
        return { deny = answer.deny }
    end
    if answer.allow == true then
        return { allow = true }
    end
    if type(answer.ask) == "string" then
        return { ask = true, title = answer.ask }
    end
    if answer.ask == true then
        return { ask = true }
    end
end

local Agent = class()

function Agent:init(session)
    self.session = session
    self.queue = {}
    self.state = "idle"
    self.confirm = function()
        return false
    end
end

function Agent:working()
    return self.state == "working"
end

function Agent:elapsed()
    return self.started and sys.os.clock() - self.started or nil
end

function Agent:begin()
    self.state = "working"
    self.started = sys.os.clock()
    event.emit("status_changed", {})
end

function Agent:finish(turn)
    self.state = "idle"
    self.started = nil
    self.task = nil
    self.turn = nil
    self.running = nil
    event.emit("tool_progress", {})
    event.emit("status_changed", {})
    if turn then
        event.emit("turn_finished", {})
    end
end

function Agent:append(message)
    local _, err = self.session:append(message)
    if err then
        notices.push(err)
    end
end

function Agent:clear_stream()
    event.emit("stream_cleared", {})
end

function Agent:delta(kind, text)
    event.emit("stream_delta", { kind = kind, text = text })
end

function Agent:sync_queue()
    event.emit("queue_changed", { count = #self.queue })
    event.emit("status_changed", {})
end

function Agent:enqueue(text)
    self.queue[#self.queue + 1] = text
    self:sync_queue()
end

function Agent:steer()
    local text = table.remove(self.queue, 1)
    if text then
        self:clear_stream()
        self:append({ type = "user", text = text })
        self:sync_queue()
    end
    return text
end

function Agent:send_queued()
    local text = table.remove(self.queue, 1)
    if text then
        self:sync_queue()
        self:submit(text)
    end
end

function Agent:repair()
    for _, call in ipairs(self.session:unanswered_calls()) do
        self:append({ type = "tool", tool_call_id = call.id, name = call.name, content = STOPPED })
    end
end

function Agent:prompt(text)
    local ok, base = pcall(function()
        return require("uji.prompt").system({ directory = self.session.directory, os = sys.os.platform })
    end)
    if not ok then
        notices.push("uji.prompt: " .. tostring(base))
        base = ""
    end
    local system, turn = context.gather(base or "")
    system = event.fold("before_turn", { text = text, system = system }, "system")
    return system, turn
end

function Agent:submit(text)
    if self:working() then
        return self:enqueue(text)
    end
    if self:compact_if_needed() then
        return self:enqueue(text)
    end
    event.emit("message_submitted", { text = text })
    self:append({ type = "user", text = text })
    self:maybe_title(text)
    local system, turn = self:prompt(text)
    for _, message in ipairs(turn) do
        self:append(message)
    end
    self:start(system)
end

function Agent:start(system)
    local Loop = require("uji.loop")
    local loop = Loop(self, {
        system = system,
        messages = view.build(self.session:entries()),
        tools = tool.specs(),
        model = model.current.model,
        effort = model.current.effort,
        max_output = model.max_output(),
        cache = model.retention(),
        session = self.session.id,
    })
    self:begin()
    self.turn = { loop = loop, calls = {}, answered = {} }
    self.task = task.spawn(function()
        local ok, err = pcall(loop.run, loop)
        if not ok then
            self:failed("uji.loop: " .. tostring(err))
        end
    end)
end

function Agent:failed(message)
    self:clear_stream()
    self:append({ type = "error", text = message })
    self:finish(true)
end

function Agent:restarted(attempt, of, wait)
    self:clear_stream()
    notices.push(string.format("request failed, retrying in %ds (%d/%d)", math.max(wait, 1), attempt, of))
end

function Agent:compacted(spent, count)
    if spent then
        self.session:add_cost(spent)
    end
    notices.push("context filled up mid-turn; compacted to continue")
    event.emit("session_compacted", { count = count })
end

function Agent:usage(spent)
    self.session:add_usage(spent)
    event.emit("status_changed", {})
end

function Agent:assistant_step(text, calls, reasoning)
    self:clear_stream()
    self:append({ type = "assistant", text = text, tool_calls = calls, reasoning = reasoning })
    if self.turn and #calls > 0 then
        self.turn.calls = calls
        self.turn.answered = {}
    end
end

function Agent:tool_running(call)
    if self.turn then
        self.turn.running = call
    end
end

function Agent:tool_result(call, content)
    event.emit("tool_progress", {})
    self:append({ type = "tool", tool_call_id = call.id, name = call.name, content = sys.lossy(content) })
    if self.turn then
        self.turn.answered[call.id] = true
        self.turn.running = nil
        self.turn.cancel_tool = nil
    end
end

function Agent:done(text, reasoning)
    self:clear_stream()
    self:append({ type = "assistant", text = text, tool_calls = {}, reasoning = reasoning })
    self:finish(true)
    self:send_queued()
end

function Agent:after_tool(name, content)
    local ok, folded = pcall(event.fold, "after_tool", { name = name, content = content }, "content")
    if not ok or type(folded) ~= "string" then
        notices.push("after_tool left no content: " .. tostring(ok and "handlers returned a " .. type(folded) or folded))
        return content
    end
    return folded
end

function Agent:verdict(name, entry, args)
    local ok, subject = pcall(tool.subject, entry, name, args)
    if not ok then
        notices.push(name .. " subject: " .. tostring(subject))
        return { ask = true }
    end
    local action = tool.compiled():evaluate(name, subject, entry and entry.policy)
    if action == "allow" then
        return { allow = true }
    elseif action == "deny" then
        return { deny = "denied by policy" }
    end
    return { ask = true }
end

function Agent:question(name, entry, args)
    local question = entry and entry.display.question or ("Would you like to run `" .. name .. "`?")
    local ok, detail = pcall(tool.detail, entry, args)
    if not ok or detail == nil then
        detail = listing(args)
    end
    return question, detail
end

function Agent:approve(name, args)
    if tool.disabled[name] then
        return { deny = name .. " is disabled" }
    end
    local entry = tool.get(name)
    local verdict = self:verdict(name, entry, args)
    local decision = decision_of(event.ask("before_tool", { name = name, arguments = args })) or verdict
    if decision.allow then
        return { allow = true, arguments = args }
    end
    if decision.deny then
        return { deny = decision.deny }
    end
    local question, detail = self:question(name, entry, args)
    local answer = self.confirm({ title = decision.title or question, body = detail, timeout = APPROVAL_TIMEOUT })
    if answer == nil then
        return { deny = "timed out waiting for confirmation" }
    end
    if answer then
        return { allow = true, arguments = args }
    end
    return { deny = "user denied" }
end

function Agent:run_tool(call, args)
    local entry = tool.get(call.name)
    event.emit("tool_started", { name = call.name })
    local promise = sys.promise()
    local ctx = {
        done = function(text)
            promise:resolve(tostring(text))
        end,
        progress = function(line)
            event.emit("tool_progress", { name = call.name, line = line })
        end,
    }
    local ok, result = pcall(entry.run, args, ctx)
    if not ok then
        return "error: " .. tostring(result)
    end
    if type(result) == "string" then
        return result
    end
    if type(result) == "function" then
        if self.turn then
            self.turn.cancel_tool = result
        end
    elseif result ~= nil then
        return "error: " .. call.name .. " returned a " .. type(result)
            .. "; run returns its result, a function that cancels it, or nothing"
    end
    return promise:await()
end

function Agent:budget()
    return model.budget()
end

function Agent:keep_recent()
    local budget = self:budget()
    local room = budget and model.usable(budget) or self.session:used_tokens()
    return math.max(math.min(context.compaction.keep_recent, math.floor(room / KEEP_CEILING_FRACTION)), 1)
end

function Agent:keep_recent_now()
    local used = self.session:used_tokens()
    return math.max(math.min(self:keep_recent(), math.floor(used / KEEP_CEILING_FRACTION)), 1)
end

function Agent:fold(messages)
    local budget = self:budget()
    if not budget then
        return nil
    end
    return compactor.fold(messages, budget, self:keep_recent())
end

function Agent:compact_if_needed()
    if not context.compaction.enabled then
        return false
    end
    local budget = self:budget()
    if not budget or self.session:used_tokens() < model.usable(budget) then
        return false
    end
    if self:compact(self:keep_recent()) then
        return true
    end
    notices.push(string.format(
        "context is over the %d token budget but the latest turn cannot be compacted",
        model.usable(budget)
    ))
    return false
end

function Agent:compact(keep)
    if self:working() then
        return false
    end
    local stored = self.session:entries()
    local cut = view.find_cut(stored, keep or self:keep_recent_now())
    if not cut then
        return false
    end
    local first = stored[cut.from].message
    local previous, carried, earlier = nil, {}, {}
    local start = cut.from
    if first.type == "compaction" then
        previous, carried = first.summary, first.files or {}
        start = cut.from + 1
    end
    for index = start, cut.compacted do
        earlier[#earlier + 1] = stored[index].message
    end
    self:begin()
    task.spawn(function()
        local files = view.merge_files(view.files_touched(earlier), carried)
        local ok, done = pcall(compactor.generate, earlier, previous)
        if ok and done then
            if done.usage then
                self.session:add_cost(done.usage)
            end
            self:append({ type = "compaction", summary = done.summary, through = cut.through, files = files })
            notices.push("compacted " .. cut.span .. " earlier messages")
            event.emit("session_compacted", { count = cut.span })
        else
            notices.push("could not compact; sending the full context")
        end
        self:finish(false)
        self:send_queued()
    end)
    return true
end

function Agent:maybe_title(first)
    if not self.session:untitled() or #self.session:entries() ~= 1 then
        return
    end
    task.spawn(function()
        local titled = title.generate(first)
        if not titled then
            return
        end
        if titled.usage then
            self.session:add_cost(titled.usage)
        end
        self:set_title(titled.title)
    end)
end

function Agent:set_title(text)
    local ok, err = pcall(self.session.rename, self.session, text)
    if not ok then
        notices.push("could not save the session title: " .. tostring(err))
        return
    end
    event.emit("session_titled", { title = text })
    event.emit("status_changed", {})
end

function Agent:interrupt()
    if self.shell then
        self.shell.cancelled = true
        self.shell.proc:kill()
        return true
    end
    if not self.task then
        return false
    end
    local turn = self.turn
    self.task:cancel()
    self.task = nil
    if self.asking then
        pcall(self.asking.close, self.asking)
        self.asking = nil
    end
    if turn and turn.cancel_tool then
        local ok, err = pcall(turn.cancel_tool)
        if not ok then
            notices.push(tostring(err))
        end
    end
    self:clear_stream()
    for _, call in ipairs(turn and turn.calls or {}) do
        if not turn.answered[call.id] then
            local content = turn.running == call and WHILE_RUNNING or BEFORE_RUNNING
            self:append({
                type = "tool",
                tool_call_id = call.id,
                name = call.name,
                content = self:after_tool(call.name, content),
            })
        end
    end
    self:append({ type = "error", text = "interrupted" })
    self:finish(true)
    return true
end

function Agent:run_shell(command)
    if self.shell then
        notices.push("a command is already running")
        return
    end
    local program = sys.os.env("SHELL") or "/bin/sh"
    local proc, err = process.spawn({ argv = { program, "-c", command }, cwd = self.session.directory })
    if not proc then
        self:append({ type = "shell", command = command, output = "spawn: " .. tostring(err), code = -1 })
        return
    end
    local name = "! " .. command
    local running = { proc = proc, command = command }
    self.shell = running
    event.emit("scroll_to_bottom", {})
    event.emit("tool_progress", { name = name, line = "" })
    event.emit("shell_started", { command = command })
    task.spawn(function()
        local capture = process.Capture(SHELL_OUTPUT)
        for line in proc:lines() do
            capture:push(line)
            event.emit("tool_progress", { name = name, line = line })
        end
        local exit = proc:wait()
        local code = running.cancelled and 130 or exit.code or -1
        local output = capture:finish()
        if running.cancelled then
            if output ~= "" then
                output = output .. "\n"
            end
            output = output .. "… interrupted"
        end
        self.shell = nil
        event.emit("tool_progress", { owner = name })
        event.emit("shell_finished", { command = command, code = code })
        self:append({ type = "shell", command = command, output = output, code = code })
    end)
end

return Agent
