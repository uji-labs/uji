local app = require("uji.core.app")
local class = require("uji.core.class")
local context = require("uji.core.context")
local event = require("uji.core.event")
local ito = require("ito")
local list = require("uji.utils.list")
local process = require("uji.core.system.process")
local sys = require("uji.sys")
local tables = require("uji.core.tables")
local task = require("uji.core.task")

local FOREGROUND = 120
local LONGEST = 2 * 60 * 60
local TAIL = 20

local M = {
    jobs = {},
    unreported = {},
    counter = 0,
    settings = { wake = true, max = 8, limit = 30 * 60 },
}

local Job = class()

function Job:init(spec)
    self.command = spec.command
    self.done = spec.done
    self.progress = spec.progress
    self.capture = process.Capture()
    self.started = sys.os.clock()
    self.state = "running"
    self.seen = 0
    self.last = ""
    ito.observable(self)
end

function Job:line(text)
    self.capture:push(text)
    self.last = text
    if self.progress then
        self.progress(text)
    end
end

function Job:tail()
    return table.concat(self.capture:since(self.capture.total - TAIL), "\n")
end

function Job:status()
    if self.state == "running" then
        return "running for " .. math.floor(sys.os.clock() - self.started) .. "s"
    elseif self.state == "finished" then
        return "finished, exit " .. self.code
    elseif self.state == "timed out" then
        return "stopped at its " .. self.limit .. "s limit"
    end
    return "stopped"
end

function M.running()
    return list.filtered(M.jobs, function(job)
        return job.state == "running"
    end)
end

local function full()
    return "the background job limit (" .. M.settings.max .. ") is reached"
end

local function result(job, text)
    if job.state == "timed out" then
        local crowded = job.crowded and ", and " .. full() or ""
        return "error: command timed out after " .. job.limit .. "s" .. crowded
    end
    if job.code == 0 then
        return text:find("%S") and text or text .. "(no output, exit code 0)"
    end
    return (text == "" and "" or text .. "\n") .. "(exit code " .. job.code .. ")"
end

local function hint(job)
    return "Read its output with job_output and id " .. job.id .. "."
end

local function ongoing(job)
    return "It keeps running, and uji tells you when it ends. " .. hint(job)
end

local function excerpt(title, job)
    local lines = job:tail()
    return lines ~= "" and "\n" .. title .. ":\n" .. lines .. "\n" or "\n"
end

local function report(job)
    local head = "Background job " .. job.id .. " (`" .. job.command .. "`) " .. job:status() .. "."
    return head .. excerpt("Last lines", job) .. hint(job)
end

local function moved(job, waited)
    local head = waited
            and "Command did not finish within its " .. waited .. "s timeout and was moved to the background as job " .. job.id .. "."
        or "The user moved this command to the background as job " .. job.id .. "."
    return head .. excerpt("Output so far", job) .. ongoing(job)
end

local function arm(job, seconds, run)
    if job.disarm then
        job.disarm()
    end
    job.limit = seconds
    job.disarm = task.defer(seconds, run)
end

local function kill(job, state)
    job.state = state
    job.handle.stop()
end

local function wake()
    task.schedule(function()
        if M.settings.wake and #M.unreported > 0 and app.agent then
            app.agent:wake()
        end
    end)
end

local function adopt(job, seconds)
    M.counter = M.counter + 1
    job.id = M.counter
    job.done, job.progress = nil, nil
    M.jobs = list.appended(M.jobs, job)
    arm(job, math.min(seconds, LONGEST), function()
        kill(job, "timed out")
    end)
end

local function detach(job, waited)
    local done = job.done
    M.foreground = nil
    adopt(job, M.settings.limit)
    done(moved(job, waited))
end

local function expire(job)
    if job.command:match("^%s*sleep%f[%s%z]") then
        return kill(job, "timed out")
    end
    if #M.running() >= M.settings.max then
        job.crowded = true
        return kill(job, "timed out")
    end
    detach(job, job.limit)
end

local function finish(job, code, reason)
    if job.disarm then
        job.disarm()
    end
    job.code = code
    if job.state == "running" then
        job.state = reason == "stopped" and "stopped" or "finished"
    end
    local text = job.capture:finish()
    if job.done then
        local done = job.done
        job.done = nil
        if M.foreground == job then
            M.foreground = nil
        end
        return done(result(job, text))
    end
    if app.agent then
        app.agent:append({
            type = "job",
            id = job.id,
            command = job.command,
            output = job:tail(),
            code = job.code,
            state = job.state,
            status = job:status(),
        })
    end
    if job.state ~= "stopped" then
        M.unreported = list.appended(M.unreported, job)
        wake()
    end
end

function M.start(spec)
    if spec.background and #M.running() >= M.settings.max then
        return nil, full() .. "; stop a job with stop_job first"
    end
    local job = Job(spec)
    local function line(text)
        job:line(text)
    end
    job.handle = process.start({
        shell = spec.command,
        cwd = spec.cwd,
        on_stdout = line,
        on_stderr = line,
        on_exit = function(code, reason)
            finish(job, code, reason)
        end,
    })
    job.handle.close()
    local seconds = spec.timeout and math.max(spec.timeout, 1)
    if spec.background then
        adopt(job, seconds or M.settings.limit)
        return job
    end
    M.foreground = job
    arm(job, seconds or FOREGROUND, function()
        expire(job)
    end)
    return job
end

function M.started(job)
    return "Started in the background as job " .. job.id .. ". " .. ongoing(job)
end

function M.background()
    local job = M.foreground
    if not job or job.state ~= "running" then
        return nil, "no command is running"
    end
    if #M.running() >= M.settings.max then
        return nil, full()
    end
    detach(job)
    return job
end

function M.get(id)
    for _, job in ipairs(M.jobs) do
        if job.id == id then
            return job
        end
    end
end

function M.stop(job)
    if not job or job.state ~= "running" then
        return false
    end
    kill(job, "stopped")
    return true
end

function M.output(job)
    local lines, skipped, seen = job.capture:since(job.seen)
    job.seen = seen
    local parts = { "job " .. job.id .. " (`" .. job.command .. "`) " .. job:status() }
    if skipped > 0 then
        local saved = job.capture.path and "; the full output is in " .. job.capture.path or ""
        parts[#parts + 1] = "[" .. skipped .. " earlier lines are no longer kept" .. saved .. "]"
    end
    parts[#parts + 1] = #lines > 0 and table.concat(lines, "\n") or "(no new output)"
    return table.concat(parts, "\n")
end

function M.list()
    return M.jobs
end

function M.configure(opts)
    M.settings = tables.merged(M.settings, opts)
end

context.add("jobs", function()
    if #M.unreported == 0 then
        return nil
    end
    local reports = list.mapped(M.unreported, report)
    M.unreported = {}
    return { text = table.concat(reports, "\n\n"), at = "turn" }
end)

event.on("turn_finished", wake)

event.on("before_quit", function()
    for _, job in ipairs(M.jobs) do
        M.stop(job)
    end
    M.stop(M.foreground)
end)

return ito.observable(M)
