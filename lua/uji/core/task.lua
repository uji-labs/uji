local list = require("uji.utils.list")
local sys = require("uji.sys")

local M = {}

local unpack = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

M.pack = pack
M.unpack = function(values, from)
    return unpack(values, from or 1, values.n)
end

local contexts = setmetatable({}, { __mode = "k" })

function M.ctx()
    return contexts[coroutine.running()] or {}
end

local function inherit(fn, ctx)
    ctx = ctx or contexts[coroutine.running()]
    if not ctx then
        return fn
    end
    return function(...)
        contexts[coroutine.running()] = ctx
        return fn(...)
    end
end

function M.spawn(fn, ...)
    return sys.task.spawn(inherit(fn), ...)
end

function M.spawn_in(ctx, fn, ...)
    return sys.task.spawn(inherit(fn, ctx), ...)
end

function M.schedule(fn, ...)
    local args = pack(...)
    local run = inherit(function()
        fn(unpack(args, 1, args.n))
    end)
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
    local task = sys.task.spawn(inherit(function()
        sys.sleep(seconds)
        fn(unpack(args, 1, args.n))
    end))
    return function()
        task:cancel()
    end
end

local function guarded(fn)
    local run = inherit(fn)
    return function()
        return pack(pcall(run))
    end
end

local function settle(outcome)
    if not outcome[1] then
        error(outcome[2], 0)
    end
    return unpack(outcome, 2, outcome.n)
end

function M.race(...)
    local racers = list.mapped({ ... }, guarded)
    local index, outcome = sys.task.race(unpack(racers))
    return index, settle(outcome)
end

function M.timeout(seconds, fn)
    if not seconds then
        return true, fn()
    end
    local finished, outcome = sys.task.timeout(seconds, guarded(fn))
    if not finished then
        return false
    end
    return true, settle(outcome)
end

function M.sequence()
    local last
    return function(fn)
        local before, done = last, sys.promise()
        last = done
        sys.task.spawn(inherit(function()
            if before then
                before:await()
            end
            local ok, err = pcall(fn)
            done:resolve()
            if not ok then
                error(err, 0)
            end
        end))
    end
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
        local task = sys.task.spawn(inherit(function()
            last(run(unpack(args, 1, args.n)))
        end))
        return function()
            task:cancel()
        end
    end
end

return M
