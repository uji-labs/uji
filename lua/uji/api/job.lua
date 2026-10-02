local app = require("uji.core.app")
local check = require("uji.core.check")
local notices = require("uji.core.notices")
local process = require("uji.core.system.process")
local task = require("uji.core.task")

local function call(handler, ...)
    if handler then
        local ok, err = pcall(handler, ...)
        if not ok then
            notices.push("job: " .. tostring(err))
        end
    end
end

local function start(opts)
    local command = process.argv(opts.cmd)
    local cwd = opts.cwd or app.directory()
    local job = { stopped = false }
    local proc, err = process.spawn({ argv = command, cwd = cwd, stdin = true })
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
        local result = process.watch(proc, opts.timeout, function(stream, line)
            call(stream == "stderr" and opts.on_stderr or opts.on_stdout, line)
        end)
        if result.timed_out then
            return call(opts.on_exit, -1, "timeout")
        end
        if job.stopped then
            return call(opts.on_exit, -1, "stopped")
        end
        call(opts.on_exit, result.code)
    end)
    local queue = task.sequence()
    return {
        send = function(text)
            local data = tostring(text)
            if data:sub(-1) ~= "\n" then
                data = data .. "\n"
            end
            queue(function()
                proc:write(data)
            end)
        end,
        close = function()
            queue(function()
                proc:close()
            end)
        end,
        stop = function()
            job.stopped = true
            proc:kill()
        end,
    }
end

uji.job = {
    start = function(opts)
        return start(check.options(opts, "uji.job.start"))
    end,
}
