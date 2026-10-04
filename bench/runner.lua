local root = ...
local sys = require("uji.sys")

local BATCH = 0.01
local SAMPLES = 10
local BUDGET = 2
local HUNG = 60

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local params = sys.json.decode(read(root .. "/bench.json"), { nulls = false })
package.path = table.concat({ params.dir .. "/?.lua", params.support .. "/?.lua" }, ";")

local Context = require("steps")
local screen = require("support.ui")
local ui = require("uji.core.ui")

local SCENARIOS = params.dir .. "/scenario"

local function wanted(name)
    if #params.filters == 0 then
        return true
    end
    for _, filter in ipairs(params.filters) do
        if name:find(filter, 1, true) then
            return true
        end
    end
    return false
end

local function batch(run, count)
    local frames
    local started = sys.os.clock()
    for _ = 1, count do
        frames = run()
    end
    return sys.os.clock() - started, frames
end

local function measure(ctx, name, steps)
    local function once()
        ctx.frames = 0
        ctx:run(steps)
        ctx:frame()
        return ctx.frames
    end
    local count = 1
    while batch(once, count) < BATCH do
        count = count * 2
    end
    local samples, frames = {}, nil
    for index = 1, SAMPLES do
        collectgarbage()
        local spent
        spent, frames = batch(once, count)
        samples[index] = spent / count
    end
    table.sort(samples)
    return { kind = "bench", name = name, seconds = samples[math.ceil(SAMPLES / 2)], frames = frames }
end

local function endure(ctx, name, steps, budget)
    collectgarbage()
    local started = sys.os.clock()
    local finished, ok, err = sys.task.timeout(HUNG, function()
        return xpcall(function()
            ctx:run(steps)
            ctx:frame()
        end, debug.traceback)
    end)
    if not finished then
        ok, err = false, string.format("did not finish within %d seconds", HUNG)
    end
    return {
        kind = "torture",
        name = name,
        seconds = sys.os.clock() - started,
        budget = budget,
        error = not ok and tostring(err) or nil,
    }
end

local function run()
    local scenarios = sys.json.decode(read(SCENARIOS .. "/scenarios.json"), { nulls = false })
    local ctx = Context(SCENARIOS, scenarios.values)
    screen.open()
    ui:render()
    local results = {}
    for _, scenario in ipairs(scenarios[params.mode][params.group]) do
        local name = params.group .. "::" .. scenario.name
        ctx:run(scenario.setup)
        ctx:prepare(scenario.run)
        if wanted(name) then
            results[#results + 1] = params.mode == "bench" and measure(ctx, name, scenario.run)
                or endure(ctx, name, scenario.run, scenario.budget or BUDGET)
        end
        ctx:run(scenario.after)
    end
    return { cases = sys.json.array(results) }
end

uji.schedule(function()
    require("uji.core.app").session.directory = params.root .. "/work"
    local ok, result = xpcall(run, debug.traceback)
    if not ok then
        result = { error = tostring(result) }
    end
    write(params.out, sys.json.encode(result))
    require("uji.core.ui"):quit()
end)
