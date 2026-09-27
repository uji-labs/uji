local sys = require("uji.sys")

local M = {}

local unpack = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

M.pack = pack
M.unpack = function(values)
    return unpack(values, 1, values.n)
end

function M.spawn(fn, ...)
    return sys.task.spawn(fn, ...)
end

function M.schedule(fn, ...)
    local args = pack(...)
    local run = function()
        fn(unpack(args, 1, args.n))
    end
    if M.held then
        M.held[#M.held + 1] = run
        return
    end
    sys.task.spawn(run)
end

function M.hold()
    M.held = M.held or {}
end

function M.release()
    local held = M.held or {}
    M.held = nil
    for _, run in ipairs(held) do
        sys.task.spawn(run)
    end
end

function M.defer(seconds, fn, ...)
    local args = pack(...)
    local task = sys.task.spawn(function()
        sys.sleep(seconds)
        fn(unpack(args, 1, args.n))
    end)
    return function()
        task:cancel()
    end
end

function M.race(...)
    local promise = sys.promise()
    local tasks = {}
    for index, fn in ipairs({ ... }) do
        tasks[index] = sys.task.spawn(function()
            promise:resolve(index, pack(pcall(fn)))
        end)
    end
    local index, outcome = promise:await()
    for _, task in ipairs(tasks) do
        task:cancel()
    end
    if not outcome[1] then
        error(outcome[2], 0)
    end
    return index, unpack(outcome, 2, outcome.n)
end

function M.timeout(seconds, fn)
    if not seconds then
        return true, fn()
    end
    local results = pack(M.race(fn, function()
        sys.sleep(seconds)
    end))
    if results[1] ~= 1 then
        return false
    end
    return true, unpack(results, 2, results.n)
end

function M.callback(run)
    return function(...)
        local count = select("#", ...)
        local last = count > 0 and select(count, ...) or nil
        if type(last) ~= "function" then
            return run(...)
        end
        local args = pack(...)
        args.n = count - 1
        local task = sys.task.spawn(function()
            last(run(unpack(args, 1, args.n)))
        end)
        return function()
            task:cancel()
        end
    end
end

return M
