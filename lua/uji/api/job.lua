local app = require("uji.app")
local notices = require("uji.notices")
local sys = require("uji.sys")
local task = require("uji.task")

local function argv(cmd)
    if type(cmd) == "string" then
        return { "sh", "-c", cmd }
    end
    if type(cmd) == "table" then
        if #cmd == 0 then
            error("cmd list must not be empty", 3)
        end
        local out = {}
        for index, part in ipairs(cmd) do
            out[index] = tostring(part)
        end
        return out
    end
    error("cmd must be a string or a list of strings", 3)
end

local function call(handler, ...)
    if handler then
        local ok, err = pcall(handler, ...)
        if not ok then
            notices.push("job: " .. tostring(err))
        end
    end
end

local function start(opts)
    local command = argv(opts.cmd)
    local cwd = opts.cwd or (app.session and app.session.directory)
    local job = { stopped = false }
    local proc, err = sys.proc.spawn(command, { cwd = cwd })
    if not proc then
        task.spawn(function()
            call(opts.on_stderr, "spawn: " .. tostring(err))
            call(opts.on_exit, -1)
        end)
        return {
            send = function() end,
            close = function() end,
            stop = function() end,
        }
    end
    task.spawn(function()
        local finished, exit = task.timeout(opts.timeout, function()
            for line, stream in proc:lines() do
                call(stream == "stderr" and opts.on_stderr or opts.on_stdout, line)
            end
            return proc:wait()
        end)
        if not finished then
            proc:kill()
            proc:wait()
            return call(opts.on_exit, -1, "timeout")
        end
        if job.stopped then
            return call(opts.on_exit, -1, "stopped")
        end
        call(opts.on_exit, exit.code or -1)
    end)
    return {
        send = function(text)
            local data = tostring(text)
            if data:sub(-1) ~= "\n" then
                data = data .. "\n"
            end
            task.spawn(function()
                proc:write(data)
            end)
        end,
        close = function()
            task.spawn(function()
                proc:close()
            end)
        end,
        stop = function()
            job.stopped = true
            proc:kill()
        end,
    }
end

return {
    start = function(opts)
        if type(opts) ~= "table" then
            error("uji.job.start needs a table", 2)
        end
        return start(opts)
    end,
}
