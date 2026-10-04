local root = ...
local sys = require("uji.sys")

local BATCH = 0.01
local SAMPLES = 10
local BUDGET = 2

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

local function measure(name, case)
    local count = 1
    while batch(case, count) < BATCH do
        count = count * 2
    end
    local samples, frames = {}, nil
    for index = 1, SAMPLES do
        collectgarbage()
        local spent
        spent, frames = batch(case, count)
        samples[index] = spent / count
    end
    table.sort(samples)
    return { kind = "bench", name = name, seconds = samples[math.ceil(SAMPLES / 2)], frames = frames }
end

local function endure(name, case, budget)
    collectgarbage()
    local started = sys.os.clock()
    local ok, err = xpcall(case, debug.traceback)
    return {
        kind = "torture",
        name = name,
        seconds = sys.os.clock() - started,
        budget = budget,
        error = not ok and tostring(err) or nil,
    }
end

local function run()
    local results = {}
    local env = setmetatable({}, { __index = _G })
    function env.bench(name, case)
        name = params.group .. "::" .. name
        if wanted(name) then
            results[#results + 1] = measure(name, case)
        end
    end
    function env.torture(name, case, opts)
        name = params.group .. "::" .. name
        if wanted(name) then
            results[#results + 1] = endure(name, case, opts and opts.budget or BUDGET)
        end
    end
    local chunk, err = loadfile(params.file, "t", env)
    if not chunk then
        error(err, 0)
    end
    chunk()
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
