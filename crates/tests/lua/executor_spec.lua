local executor = require("uji.core.executor")
local sys = require("uji.sys")

local function note(log, text, seconds)
    return function()
        log[#log + 1] = text
        sys.sleep(seconds or 0.02)
        log[#log + 1] = text .. "'"
        return text
    end
end

local function parallel(items, limit)
    return executor.Parallel(items, { limit = limit or 2 }):execute()
end

local function sequential(items)
    return executor.Sequential(items):execute()
end

it("runs the calls at the same time", function()
    local log = {}
    local run = parallel({
        { run = note(log, "a") },
        { run = note(log, "b") },
    })
    run:await()
    assert.same({ "a", "b" }, { log[1], log[2] })
    assert.equal(4, #log)
end)

it("runs a resolved call without running it", function()
    local log = {}
    local run = parallel({
        { resolved = { status = "denied", reason = "denied: user denied" } },
        { run = note(log, "r") },
    })
    local results = run:await()
    assert.equal("denied", results[1].status)
    assert.equal("denied: user denied", results[1].reason)
    assert.equal("completed", results[2].status)
    assert.same({ "r", "r'" }, log)
end)

it("keeps a failed call in its place and runs the rest", function()
    local run = parallel({
        {
            run = function()
                error("no room")
            end,
        },
        {
            run = function()
                return "read"
            end,
        },
    })
    local results = run:await()
    assert.equal("failed", results[1].status)
    assert.truthy(results[1].reason:find("no room", 1, true))
    assert.equal("read", results[2].value)
end)

it("keeps the results in call order when the later call finishes first", function()
    local run = parallel({
        {
            run = function()
                sys.sleep(0.05)
                return "slow"
            end,
        },
        {
            run = function()
                return "fast"
            end,
        },
    })
    local results = run:await()
    assert.equal("slow", results[1].value)
    assert.equal("fast", results[2].value)
end)

it("runs no more calls at once than the limit allows", function()
    local live, most = 0, 0
    local function work()
        live = live + 1
        most = math.max(most, live)
        sys.sleep(0.01)
        live = live - 1
    end
    local run = parallel({
        { run = work },
        { run = work },
        { run = work },
    })
    run:await()
    assert.equal(2, most)
end)

it("cancels the calls that are still running and leaves the finished ones", function()
    local started = sys.promise()
    local run = parallel({
        {
            run = function()
                return "kept"
            end,
        },
        {
            run = function()
                started:resolve()
                sys.sleep(1)
                return "never"
            end,
        },
        {
            run = function()
                return "never"
            end,
        },
    })
    started:await()
    run:cancel("interrupted")
    local results = run:await()
    assert.equal("completed", results[1].status)
    assert.equal("kept", results[1].value)
    assert.equal("cancelled", results[2].status)
    assert.equal("interrupted", results[2].reason)
    assert.equal("cancelled", results[3].status)
end)

it("runs a sequential batch one call after another", function()
    local log = {}
    local run = sequential({
        { run = note(log, "a") },
        { run = note(log, "b") },
        { run = note(log, "c") },
    })
    run:await()
    assert.same({ "a", "a'", "b", "b'", "c", "c'" }, log)
end)

it("cancels what is left of a sequential batch", function()
    local started = sys.promise()
    local run = sequential({
        {
            run = function()
                return "kept"
            end,
        },
        {
            run = function()
                started:resolve()
                sys.sleep(1)
                return "never"
            end,
        },
        {
            run = function()
                return "never"
            end,
        },
    })
    started:await()
    run:cancel("interrupted")
    local results = run:await()
    assert.equal("kept", results[1].value)
    assert.equal("cancelled", results[2].status)
    assert.equal("cancelled", results[3].status)
end)
