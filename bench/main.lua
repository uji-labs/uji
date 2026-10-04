local fs = require("uji.sys.fs")
local json = require("uji.sys.json")
local proc = require("uji.sys.proc")
local promise = require("uji.sys.promise")
local system = require("uji.sys.os")
local task = require("uji.sys.task")

local SCENARIOS = "/scenario/scenarios.json"
local SIZE = "120x40"
local TIMEOUT = 600
local STARTS = 10
local MILLISECOND = 1e-3
local UNITS = { { "s", 1 }, { "ms", MILLISECOND }, { "µs", 1e-6 }, { "ns", 1e-9 } }

local function say(...)
    io.stdout:write(...)
    io.stdout:flush()
end

local function parent(path)
    return path:match("^(.*)/[^/]*$") or "."
end

local function write(path, data)
    assert(fs.mkdir(parent(path)))
    assert(fs.write(path, data))
end

local function duration(seconds)
    for index, unit in ipairs(UNITS) do
        if seconds >= unit[2] or index == #UNITS then
            return string.format("%8.2f %s", seconds / unit[2], unit[1])
        end
    end
end

local function median(values)
    table.sort(values)
    return values[math.ceil(#values / 2)]
end

local function wanted(filters, name)
    if #filters == 0 then
        return true
    end
    for _, filter in ipairs(filters) do
        if name:find(filter, 1, true) then
            return true
        end
    end
    return false
end

local Run = {}
Run.__index = Run

local function options(args)
    local filters, json_path = {}, nil
    local index = 5
    while args[index] do
        if args[index] == "--json" then
            json_path = assert(args[index + 1], "--json needs a file")
            index = index + 2
        else
            filters[#filters + 1] = args[index]
            index = index + 1
        end
    end
    return filters, json_path
end

local function start(args)
    local dir = assert(fs.realpath(parent(assert(args[3], "usage: uji-test -l main.lua bench|torture [--json file] [filter...]"))))
    local mode = args[4]
    local scenarios = json.decode(assert(fs.read(dir .. SCENARIOS)), { nulls = false })
    assert(mode ~= "values" and scenarios[mode], "the mode must be bench or torture")
    local filters, json_path = options(args)
    local tmp = (system.env("TMPDIR") or "/tmp"):gsub("/$", "")
    local run = setmetatable({
        dir = dir,
        mode = mode,
        groups = scenarios[mode],
        support = assert(fs.realpath(dir .. "/../crates/tests/lua")),
        root = string.format("%s/uji-bench-%d", tmp, system.now()),
        bin = assert(system.executable, "uji-test does not know where it is"),
        filters = filters,
        json = json_path,
        results = {},
        made = 0,
        failed = 0,
    }, Run)
    assert(fs.mkdir(run.root))
    return run
end

function Run:sandbox(init)
    self.made = self.made + 1
    local root = self.root .. "/" .. self.made
    for _, sub in ipairs({ "cfg", "work", "data" }) do
        assert(fs.mkdir(root .. "/" .. sub))
    end
    if init then
        write(root .. "/cfg/init.lua", init)
    end
    return root
end

function Run:spawn(root)
    local child, err = proc.spawn({
        self.bin,
        "--screen",
        SIZE,
        "new",
        "--config-dir",
        root .. "/cfg",
        "--data-dir",
        root .. "/data",
        "--db",
        root .. "/uji.db",
    }, { cwd = root .. "/work" })
    if not child then
        return nil, err
    end
    child:close()
    local lines, done = {}, promise()
    local reader = task.spawn(function()
        for line in child:lines() do
            lines[#lines + 1] = line
        end
        done:resolve()
    end)
    local finished = task.timeout(TIMEOUT, function()
        child:wait()
    end)
    if not finished then
        child:kill()
        child:wait()
    end
    task.timeout(1, function()
        done:await()
    end)
    reader:cancel()
    return finished, table.concat(lines, "\n")
end

function Run:startup()
    local name = "startup::boot and quit"
    if self.mode ~= "bench" or not wanted(self.filters, name) then
        return
    end
    local root = self:sandbox('uji.schedule(function() require("uji.core.ui"):quit() end)\n')
    local times = {}
    for index = 1, STARTS do
        local started = system.clock()
        assert(self:spawn(root), "uji did not quit")
        times[index] = system.clock() - started
    end
    self:report({ kind = "bench", name = name, seconds = median(times) })
end

function Run:fail(name, problem)
    self.failed = self.failed + 1
    say(string.format("FAIL  %s: %s\n", name, problem))
end

function Run:group(name)
    local out = self.root .. "/" .. name .. ".json"
    local root = self:sandbox()
    write(
        root .. "/bench.json",
        json.encode({
            root = root,
            dir = self.dir,
            support = self.support,
            group = name,
            mode = self.mode,
            filters = json.array(self.filters),
            out = out,
        })
    )
    write(root .. "/cfg/init.lua", string.format("assert(loadfile(%q))(%q)\n", self.dir .. "/runner.lua", root))
    local finished, output = self:spawn(root)
    local text = fs.read(out)
    if not finished or not text then
        return self:fail(name, string.format("uji %s\n%s", finished and "left no result" or "ran too long", output))
    end
    local result = json.decode(text, { nulls = false })
    if result.error then
        return self:fail(name, result.error)
    end
    for _, case in ipairs(result.cases) do
        self:report(case)
    end
end

function Run:report(case)
    self.results[#self.results + 1] = case
    if case.kind == "bench" then
        local frames = case.frames
                and case.frames > 1
                and string.format("  %s/frame over %d frames", duration(case.seconds / case.frames), case.frames)
            or ""
        say(string.format("%-48s %s%s\n", case.name, duration(case.seconds), frames))
        return
    end
    local state = case.error and "FAIL" or case.seconds > case.budget and "SLOW" or "ok"
    if state ~= "ok" then
        self.failed = self.failed + 1
    end
    local detail = case.error or state == "SLOW" and string.format("over its %s budget", duration(case.budget)) or ""
    say(string.format("%-5s %-48s %s  %s\n", state, case.name, duration(case.seconds), detail))
end

function Run:all()
    local groups = {}
    for name in pairs(self.groups) do
        groups[#groups + 1] = name
    end
    table.sort(groups)
    self:startup()
    for _, name in ipairs(groups) do
        self:group(name)
    end
    if self.json then
        local entries = {}
        for _, case in ipairs(self.results) do
            if case.kind == "bench" then
                entries[#entries + 1] = { name = case.name, unit = "ms", value = case.seconds / MILLISECOND }
            end
        end
        write(self.json, json.encode(json.array(entries)))
    end
    if self.failed == 0 then
        fs.remove(self.root, { recursive = true })
    else
        say("sandboxes are kept in ", self.root, "\n")
    end
end

return function(args)
    local run = start(args)
    run:all()
    system.exit(run.failed > 0 and 1 or 0)
end
