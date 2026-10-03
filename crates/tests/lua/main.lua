local fs = require("uji.sys.fs")
local json = require("uji.sys.json")
local proc = require("uji.sys.proc")
local promise = require("uji.sys.promise")
local system = require("uji.sys.os")
local task = require("uji.sys.task")

local SUFFIX = "_spec.lua"
local SIZE = { 80, 24 }
local TIMEOUT = 30
local JOBS = 4

local function parent(path)
    return path:match("^(.*)/[^/]*$") or "."
end

local function write(path, data)
    assert(fs.mkdir(parent(path)))
    assert(fs.write(path, data))
end

local function stem(file)
    return file:match("([^/]+)" .. SUFFIX .. "$")
end

local function collect(child)
    local lines, done = {}, promise()
    local reader = task.spawn(function()
        for line in child:lines() do
            lines[#lines + 1] = line
        end
        done:resolve()
    end)
    return lines, function()
        task.timeout(1, function()
            done:await()
        end)
        reader:cancel()
    end
end

local function command(argv, cwd)
    local child, err = proc.spawn(argv, { cwd = cwd })
    if not child then
        return nil, err
    end
    child:close()
    local lines, drain = collect(child)
    local exit = child:wait()
    drain()
    return exit, lines
end

local function jobs()
    local count = tonumber(system.env("UJI_TEST_JOBS") or "")
    if count then
        return count
    end
    local exit, lines = command({ "getconf", "_NPROCESSORS_ONLN" })
    return exit and exit.code == 0 and tonumber(lines[1]) or JOBS
end

local Run = {}
Run.__index = Run

local function start(args)
    local file = assert(args[3], "usage: uji-test -l main.lua [filter...]")
    local dir = assert(fs.realpath(parent(file)))
    local tmp = (system.env("TMPDIR") or "/tmp"):gsub("/$", "")
    local run = setmetatable({
        dir = dir,
        repo = assert(fs.realpath(dir .. "/../../..")),
        root = string.format("%s/uji-test-%d", tmp, system.now()),
        bin = assert(system.executable, "uji-test does not know where it is"),
        filters = { unpack(args, 4) },
        made = 0,
    }, Run)
    assert(fs.mkdir(run.root))
    return run
end

function Run:sandbox()
    self.made = self.made + 1
    local root = self.root .. "/" .. self.made
    for _, sub in ipairs({ "cfg", "work", "data" }) do
        assert(fs.mkdir(root .. "/" .. sub))
    end
    return root
end

function Run:boot(root, params, size, timeout)
    params.root = root
    params.lua = self.dir
    params.bin = self.bin
    params.out = root .. "/result.json"
    write(root .. "/test.json", json.encode(params))
    write(root .. "/cfg/init.lua", string.format("assert(loadfile(%q))(%q)\n", self.dir .. "/runner.lua", root))
    local child, err = proc.spawn({
        self.bin,
        "--screen",
        size[1] .. "x" .. size[2],
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
    local lines, drain = collect(child)
    local finished, exit = task.timeout(timeout, function()
        return child:wait()
    end)
    if not finished then
        child:kill()
        child:wait()
        drain()
        return nil, string.format("ran past its %ss deadline", timeout)
    end
    drain()
    local text = fs.read(params.out)
    if not text then
        return nil, string.format("left no result; uji exited with %s\n%s", tostring(exit.code), table.concat(lines, "\n"))
    end
    return json.decode(text, { nulls = false })
end

function Run:list()
    local files = {}
    for _, entry in ipairs(assert(fs.list(self.dir))) do
        if entry.name:sub(-#SUFFIX) == SUFFIX then
            files[#files + 1] = self.dir .. "/" .. entry.name
        end
    end
    table.sort(files)
    local result, err = self:boot(self:sandbox(), { mode = "list", files = json.array(files) }, SIZE, TIMEOUT)
    if not result then
        error("could not list the tests: " .. err, 0)
    end
    if result.error then
        error(result.error, 0)
    end
    local tests = {}
    for _, test in ipairs(result.tests) do
        test.full = stem(test.file) .. "::" .. (test.name or "load")
        if self:wanted(test.full) then
            tests[#tests + 1] = test
        end
    end
    return tests
end

function Run:wanted(name)
    if #self.filters == 0 then
        return true
    end
    for _, filter in ipairs(self.filters) do
        if name:find(filter, 1, true) then
            return true
        end
    end
    return false
end

function Run:build()
    local cargo = system.env("CARGO") or "cargo"
    local target = (system.env("CARGO_TARGET_DIR") or self.repo .. "/target") .. "/uji-test-module"
    local exit, lines = command({
        cargo,
        "build",
        "--manifest-path",
        self.dir .. "/../module/Cargo.toml",
        "--target-dir",
        target,
        "--message-format",
        "json",
    })
    if not exit or exit.code ~= 0 then
        return nil, "cargo could not build the test module\n" .. table.concat(lines or {}, "\n")
    end
    for _, line in ipairs(lines) do
        local ok, message = pcall(json.decode, line, { nulls = false })
        if ok and type(message) == "table" and message.reason == "compiler-artifact" then
            local kind = message.target and message.target.kind or {}
            for _, path in ipairs(kind[1] == "cdylib" and message.filenames or {}) do
                if path:sub(-#system.library - 1) == "." .. system.library then
                    return path
                end
            end
        end
    end
    return nil, "cargo built no test module"
end

function Run:library()
    if not self.built then
        self.built = promise()
        self.built:resolve(self:build())
    end
    return self.built:await()
end

function Run:prepare(root, test)
    for relative, content in pairs(test.config or {}) do
        write(root .. "/cfg/" .. relative, content)
    end
    for _, module in ipairs(test.native or {}) do
        local path, err = self:library()
        if not path then
            return err
        end
        write(root .. "/cfg/native/" .. module .. "." .. system.library, assert(fs.read(path)))
    end
end

function Run:test(test)
    if test.error then
        return test.error
    end
    local root = self:sandbox()
    local problem = self:prepare(root, test)
    if problem then
        return problem
    end
    local size = { test.width or SIZE[1], test.height or SIZE[2] }
    local result, err = self:boot(root, { mode = "run", file = test.file, test = test.name }, size, test.timeout or TIMEOUT)
    if not result then
        return err
    end
    if result.ok then
        fs.remove(root, { recursive = true })
        return nil
    end
    return result.error or "the test failed"
end

local function say(...)
    io.stdout:write(...)
    io.stdout:flush()
end

function Run:all(tests)
    local index, failures, started = 0, {}, system.clock()
    local finished = promise()
    local active = math.max(1, math.min(jobs(), #tests))
    for _ = 1, active do
        task.spawn(function()
            while index < #tests do
                index = index + 1
                local test = tests[index]
                local began = system.clock()
                local ok, problem = pcall(self.test, self, test)
                if not ok then
                    problem = tostring(problem)
                end
                say(string.format("%s [%6.2fs] %s\n", problem and "FAIL" or "PASS", system.clock() - began, test.full))
                if problem then
                    failures[#failures + 1] = { name = test.full, problem = problem }
                end
            end
            active = active - 1
            if active == 0 then
                finished:resolve()
            end
        end)
    end
    finished:await()
    table.sort(failures, function(a, b)
        return a.name < b.name
    end)
    for _, failure in ipairs(failures) do
        say("\n--- ", failure.name, "\n    ", (failure.problem:gsub("\n", "\n    ")), "\n")
    end
    local noun = #tests == 1 and "test" or "tests"
    say(string.format("\n%d %s: %d passed, %d failed in %.2fs\n", #tests, noun, #tests - #failures, #failures, system.clock() - started))
    if #failures == 0 then
        fs.remove(self.root, { recursive = true })
    else
        say("failed sandboxes are kept in ", self.root, "\n")
    end
    return #failures
end

return function(args)
    local run = start(args)
    local tests = run:list()
    if #tests == 0 then
        say("no tests match ", table.concat(run.filters, " "), "\n")
        return system.exit(1)
    end
    system.exit(run:all(tests) > 0 and 1 or 0)
end
