local agent = require("support.agent")
local app = require("uji.core.app")
local jobs = require("uji.core.jobs")
local keys = require("uji.core.ui.keys")
local list = require("uji.utils.list")
local sandbox = require("support.sandbox")
local screen = require("support.ui")
local server = require("support.server")
local sys = require("uji.sys")
local tool = require("uji.core.tool")
local ui = require("uji.core.ui")
local wait = require("support.wait")

local eventually = wait.eventually

local function has(value, part)
    return tostring(value):find(part, 1, true) ~= nil
end

local function ended()
    local job = uji.jobs.list()[1]
    return job and job.state ~= "running"
end

local function finished(count)
    local done, seen = sys.promise(), 0
    uji.on("turn_finished", function()
        seen = seen + 1
        if seen == count then
            done:resolve()
        end
    end)
    return done
end

local function run(arguments)
    return { "run_command", sys.json.encode(arguments) }
end

local function script(calls)
    return agent.serve(function(round)
        if calls[round + 1] then
            return server.tool_calls(round, { calls[round + 1] })
        end
        return server.text("ok")
    end)
end

local function sent(mock)
    local turns = mock:turns()
    return sys.json.encode(turns[#turns].body.messages)
end

it("starts a background job and wakes the model when it ends", { timeout = 10 }, function()
    local mock = script({ run({ command = "echo built; sleep 0.3; echo done", run_in_background = true }) })
    agent.allow_all()
    local woken = finished(2)
    local result = agent.tool_results(agent.run({ url = mock.url }))[1]
    assert.is_true(has(result, "Started in the background as job 1"), result)
    woken:await()
    assert.is_true(has(sent(mock), "Background job 1 (`echo built; sleep 0.3; echo done`) finished, exit 0"))
    assert.is_true(has(sent(mock), "done"))
    local reported
    for _, message in ipairs(app.session:messages()) do
        if message.type == "job" then
            reported = message
        end
    end
    assert.is_not_nil(reported)
    assert.equal("echo built; sleep 0.3; echo done", reported.command)
    assert.equal("finished, exit 0", reported.status)
    assert.is_true(has(reported.output, "done"), reported.output)
    ui:take_notices()
    assert.is_nil(ui.flashed, "a finished job joins the chat, not the notices")
end)

it("moves a command to the background at its timeout", { timeout = 10 }, function()
    local mock = script({ run({ command = "echo first; sleep 2; echo second", timeout = 1 }) })
    agent.allow_all()
    local woken = finished(2)
    local result = agent.tool_results(agent.run({ url = mock.url }))[1]
    assert.is_true(has(result, "Command did not finish within its 1s timeout and was moved to the background as job 1."), result)
    assert.is_true(has(result, "Output so far:\nfirst"), result)
    woken:await()
    assert.is_true(has(sent(mock), "second"))
end)

it("stops a sleep at its timeout instead of moving it", { timeout = 10 }, function()
    local mock = script({ run({ command = "sleep 3", timeout = 1 }) })
    agent.allow_all()
    local result = agent.tool_results(agent.run({ url = mock.url }))[1]
    assert.equal("error: command timed out after 1s", result)
    assert.same({}, uji.jobs.list())
end)

it("moves the running command to the background with ctrl z", { timeout = 10 }, function()
    local mock = script({ run({ command = "echo go; sleep 1; echo end" }) })
    agent.allow_all()
    local woken = finished(2)
    uji.defer(0, function()
        for _ = 1, 100 do
            if #uji.jobs.list() > 0 then
                return
            end
            ui:key(keys.parse("<C-z>"))
            sys.sleep(0.02)
        end
    end)
    local result = agent.tool_results(agent.run({ url = mock.url }))[1]
    assert.is_true(has(result, "The user moved this command to the background as job 1."), result)
    woken:await()
    assert.is_true(has(sent(mock), "end"))
end)

it("keeps background jobs running when the turn is interrupted", { timeout = 10 }, function()
    local mock = script({
        run({ command = "sleep 1.5; echo later", run_in_background = true }),
        run({ command = "sleep 5" }),
    })
    agent.allow_all()
    local woken = finished(2)
    uji.defer(0, function()
        eventually(function()
            return uji.jobs.list()[1] ~= nil
        end)
        uji.session.interrupt()
    end)
    assert.equal("interrupted", agent.last_error(agent.run({ url = mock.url })))
    assert.equal("running", uji.jobs.list()[1].state)
    woken:await()
    assert.is_true(has(sent(mock), "later"))
end)

it("stops a job with stop_job and refuses one over the limit", { timeout = 10 }, function()
    uji.jobs.configure({ max = 1 })
    local mock = script({
        run({ command = "sleep 5", run_in_background = true }),
        run({ command = "sleep 5", run_in_background = true }),
        { "stop_job", '{"id":1}' },
        { "job_output", '{"id":99}' },
    })
    agent.allow_all()
    local results = agent.tool_results(agent.run({ url = mock.url }))
    assert.is_true(has(results[2], "the background job limit (1) is reached; stop a job with stop_job first"), results[2])
    assert.equal("stopped job 1", results[3])
    assert.equal("error: there is no job 99; use an id run_command gave", results[4])
    eventually(ended)
    assert.equal("stopped", uji.jobs.list()[1].state)
    sys.sleep(0.2)
    assert.equal(5, #mock:turns(), "a stopped job wakes nobody")
end)

it("names jobs in the theme's words and reports a stopped one in the chat", { size = { 60, 12 }, timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    uji.ui.configure({ theme = require("uji.themes.default")({ text = { job = "run %d" } }) })
    jobs.start({ command = "echo hi; sleep 5", cwd = sandbox.work, background = true })
    eventually(function()
        return uji.jobs.list()[1].tail == "hi"
    end)
    assert.is_nil(screen.find("run 1  echo hi; sleep 5  hi"), "the footer leaves a running job alone")
    assert.is_not_nil(screen.find("run 1  echo hi; sleep 5"), "the panel lists the running job")
    local asked
    uji.ui.pick = function(opts)
        asked = opts
        return opts.items[1]
    end
    require("uji.core.command").run("jobs")
    assert.is_true(has(asked.label(asked.items[1]), "run 1  running for"))
    assert.equal("run 1", tool.detail(tool.get("stop_job"), { id = 1 }))
    assert.same({ "hi" }, asked.preview(asked.items[1]))
    eventually(ended)
    assert.equal("stopped", uji.jobs.list()[1].state)
    eventually(function()
        return screen.find("Job(echo hi; sleep 5) stopped") ~= nil
    end)
    ui:take_notices()
    assert.is_nil(ui.flashed, "a stopped job joins the chat, not the notices")
end)

it("shows the running jobs first, then the newest", { timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    local asked
    uji.ui.pick = function(opts)
        asked = opts
    end
    jobs.start({ command = "echo one", background = true })
    jobs.start({ command = "echo two", background = true })
    jobs.start({ command = "sleep 5", background = true })
    eventually(function()
        local listed = uji.jobs.list()
        return listed[1].state == "finished" and listed[2].state == "finished" and listed[3].state == "running"
    end)
    require("uji.core.command").run("jobs")
    assert.same(
        { 3, 2, 1 },
        list.mapped(asked.items, function(job)
            return job.id
        end)
    )
end)

it("waits for your next message when waking is off", { timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    local mock = script({ run({ command = "sleep 0.3; echo quiet", run_in_background = true }) })
    agent.allow_all()
    agent.run({ url = mock.url })
    eventually(ended)
    local before = #mock:turns()
    assert.is_false(app.agent:working())
    local next = finished(1)
    uji.session.submit("anything new?")
    next:await()
    assert.equal(before + 1, #mock:turns())
    assert.is_true(has(sent(mock), "quiet"))
end)

it("binds ctrl z to the background action without taking alt b from word left", function()
    local bound = {}
    for _, row in ipairs(uji.keymap.list()) do
        if row.mode == "normal" then
            bound[row.key] = row.action
        end
    end
    assert.equal("background", bound["<C-z>"])
    assert.equal("word_left", bound["<A-b>"])
end)

it("does not move a command that was just stopped", function()
    local job = jobs.start({ command = "sleep 5", cwd = sandbox.work, timeout = 60, done = function() end })
    jobs.stop(job)
    local moved, err = jobs.background()
    assert.is_nil(moved)
    assert.equal("no command is running", err)
    assert.same({}, uji.jobs.list())
end)

it("stops the server a job started when it stops the job", { timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    local saved = sandbox.work .. "/server.pid"
    local job = jobs.start({ command = "sleep 30 & echo $! > " .. saved .. "; wait", cwd = sandbox.work, background = true })
    local pid
    eventually(function()
        pid = (sys.fs.read(saved) or ""):match("%d+")
        return pid ~= nil
    end)
    assert.is_true(wait.alive(pid))
    jobs.stop(job)
    eventually(function()
        return not wait.alive(pid)
    end)
end)

it("selects a job below the input, opens it, stops it and drops its row", { size = { 80, 12 }, timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    local job = jobs.start({ command = "echo hi; sleep 1; echo later; sleep 5", cwd = sandbox.work, background = true })
    eventually(function()
        return screen.find("job 1  echo hi; sleep 1; echo later; sleep 5") ~= nil
    end)
    screen.press("up")
    assert.equal(job.id, ui.jobs.selected)
    screen.press("enter")
    assert.is_true(ui.modal ~= nil, "enter opens the job's output")
    eventually(function()
        return screen.find("later") ~= nil
    end)
    screen.press("esc")
    assert.is_nil(ui.modal, "esc closes it")
    screen.press("x")
    eventually(function()
        return uji.jobs.list()[1].state == "stopped"
    end)
    assert.is_not_nil(screen.find("✗ job 1"), "a stopped job keeps its row")
    screen.press("x")
    assert.is_nil(ui.jobs.selected, "a dropped row is let go")
    eventually(function()
        return screen.find("✗ job 1") == nil
    end)
end)

it("says where a finished job went", { size = { 80, 12 }, timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    jobs.start({ command = "echo hi", cwd = sandbox.work, background = true })
    eventually(function()
        return screen.find("/jobs to see finished jobs") ~= nil
    end)
    assert.is_nil(screen.find("job 1  echo hi"), "a job that worked leaves no row")
end)

it("leaves the jobs hint to jobs, not to a command that just ran", { size = { 80, 12 }, timeout = 10 }, function()
    local mock = script({ run({ command = "echo hi" }) })
    agent.allow_all()
    agent.run({ url = mock.url })
    eventually(function()
        return screen.find("ok") ~= nil
    end)
    assert.is_nil(screen.find("/jobs to see finished jobs"), "a foreground command is not a job")
end)

it("keeps a failed job's row for a while and no longer", { timeout = 5 }, function()
    local now = sys.os.clock()
    jobs.jobs = {
        { id = 1, state = "finished", code = 1, command = "boom", started = now - 5, ended = now - 1 },
        { id = 2, state = "stopped", command = "stop", started = now - 40, ended = now - 31 },
        { id = 3, state = "finished", code = 0, command = "fine", started = now - 5, ended = now - 1 },
    }
    ui.jobs:refresh()
    local rows = ui.jobs.rows
    assert.same(
        { 1 },
        list.mapped(rows, function(row)
            return row.id
        end)
    )
    assert.is_true(ui:busy(), "a row that is still shown keeps the screen moving")
end)

it("lists at most five jobs, running ones first", { timeout = 5 }, function()
    local now = sys.os.clock()
    local started = {}
    for index = 1, 7 do
        started[index] = {
            id = index,
            state = index > 5 and "finished" or "running",
            code = 0,
            command = "job " .. index,
            started = now,
        }
    end
    jobs.jobs = started
    ui.jobs:refresh()
    assert.equal(5, #ui.jobs.rows)
    assert.equal(1, ui.jobs.rows[1].id)
    assert.equal(5, ui.jobs.rows[5].id)
end)

it("keeps the selection on its job when the rows move", { size = { 80, 12 }, timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    local first = jobs.start({ command = "sleep 1", cwd = sandbox.work, background = true })
    local second = jobs.start({ command = "sleep 5", cwd = sandbox.work, background = true })
    eventually(function()
        return #ui.jobs.rows == 2
    end)
    screen.press("up")
    screen.rows()
    screen.press("down")
    assert.equal(second.id, ui.jobs.selected)
    eventually(function()
        return uji.jobs.list()[1].state == "finished"
    end)
    eventually(function()
        return #ui.jobs.rows == 1
    end)
    assert.equal(second.id, ui.jobs.selected, "the selection follows its job, not its row")
    assert.equal(first.id, uji.jobs.list()[1].id)
end)

it("lets go of the panel when you type", { size = { 80, 12 }, timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    jobs.start({ command = "sleep 5", cwd = sandbox.work, background = true })
    eventually(function()
        return #ui.jobs.rows == 1
    end)
    screen.press("up")
    assert.is_not_nil(ui.jobs.selected)
    screen.press("a")
    assert.is_nil(ui.jobs.selected, "typing gives the prompt back")
    assert.equal("a", ui.composer:text())
end)
