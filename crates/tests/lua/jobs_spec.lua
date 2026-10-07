local agent = require("support.agent")
local app = require("uji.core.app")
local jobs = require("uji.core.jobs")
local keys = require("uji.core.ui.keys")
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
    ui:take_notices()
    assert.is_true(has(table.concat(ui.notices, "\n"), "job 1 (echo built; sleep 0.3; echo done) finished, exit 0"))
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
    uji.defer(0.3, function()
        ui:key(keys.parse("<C-z>"))
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
    uji.defer(0.3, uji.session.interrupt)
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

it("shows running jobs in the theme's words and stops one from /jobs", { size = { 60, 12 }, timeout = 10 }, function()
    uji.jobs.configure({ wake = false })
    uji.ui.configure({ theme = require("uji.themes.default")({ text = { job = "task %d" } }) })
    jobs.start({ command = "echo hi; sleep 5", cwd = sandbox.work, background = true })
    eventually(function()
        return uji.jobs.list()[1].tail == "hi"
    end)
    assert.is_not_nil(screen.find("task 1  echo hi; sleep 5  hi"))
    local asked
    uji.ui.pick = function(opts)
        asked = opts
        return opts.items[1]
    end
    require("uji.core.command").run("jobs")
    assert.is_true(has(asked.label(asked.items[1]), "task 1  running for"))
    assert.equal("task 1", tool.detail(tool.get("stop_job"), { id = 1 }))
    assert.same({ "hi" }, asked.preview(asked.items[1]))
    eventually(ended)
    assert.equal("stopped", uji.jobs.list()[1].state)
    eventually(function()
        ui:take_notices()
        return has(table.concat(ui.notices, "\n"), "task 1 (echo hi; sleep 5) stopped")
    end)
    screen.rows(true)
    assert.is_nil(screen.find("task 1  echo hi"))
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
