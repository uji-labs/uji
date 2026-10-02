local root = ...
local sys = require("uji.sys")

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

local params = sys.json.decode(read(root .. "/test.json"), { nulls = false })
local dir = params.lua
package.path = table.concat({
    dir .. "/?.lua",
    dir .. "/?/init.lua",
    dir .. "/vendor/?.lua",
    dir .. "/vendor/?/init.lua",
}, ";")
package.loaded["support.params"] = params

local function joined(names, name)
    local out = { unpack(names) }
    out[#out + 1] = name
    return out
end

local function collect(file)
    local tests = {}
    local block = { names = {}, before = {}, after = {} }
    local env = setmetatable({
        assert = require("luassert"),
        spy = require("luassert.spy"),
        stub = require("luassert.stub"),
        mock = require("luassert.mock"),
        match = require("luassert.match"),
    }, { __index = _G })
    function env.describe(name, body)
        local parent = block
        block = { parent = parent, names = joined(parent.names, name), before = {}, after = {} }
        body()
        block = parent
    end
    function env.it(name, opts, body)
        if body == nil then
            opts, body = {}, opts
        end
        tests[#tests + 1] = {
            name = table.concat(joined(block.names, name), " "),
            opts = opts,
            body = body,
            block = block,
        }
    end
    function env.before_each(fn)
        block.before[#block.before + 1] = fn
    end
    function env.after_each(fn)
        block.after[#block.after + 1] = fn
    end
    local chunk, err = loadfile(file, "t", env)
    if not chunk then
        error(err, 0)
    end
    chunk()
    return tests
end

local RUNNER = debug.getinfo(1, "S").source:sub(2)

local function trace(err)
    if type(err) ~= "string" then
        err = sys.message(err)
    end
    local lines, frames = {}, false
    for line in debug.traceback(err, 2):gmatch("[^\n]+") do
        if frames and line:find(RUNNER, 1, true) then
            break
        end
        frames = frames or line == "stack traceback:"
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
end

local function chain(block)
    local out = {}
    while block do
        table.insert(out, 1, block)
        block = block.parent
    end
    return out
end

local function run(test)
    local blocks = chain(test.block)
    local ok, err = xpcall(function()
        for _, block in ipairs(blocks) do
            for _, fn in ipairs(block.before) do
                fn()
            end
        end
        test.body()
    end, trace)
    for at = #blocks, 1, -1 do
        for _, fn in ipairs(blocks[at].after) do
            local cleaned, problem = xpcall(fn, trace)
            if ok and not cleaned then
                ok, err = false, problem
            end
        end
    end
    return ok, err
end

local function listed()
    local out = {}
    for _, file in ipairs(params.files) do
        local ok, tests = xpcall(collect, trace, file)
        if not ok then
            out[#out + 1] = { file = file, error = tests }
        else
            for _, test in ipairs(tests) do
                local size = test.opts.size or {}
                out[#out + 1] = {
                    file = file,
                    name = test.name,
                    width = size[1],
                    height = size[2],
                    timeout = test.opts.timeout,
                    native = test.opts.native and sys.json.array(test.opts.native),
                    config = test.opts.config,
                }
            end
        end
    end
    return { tests = sys.json.array(out) }
end

local function ran()
    for _, test in ipairs(collect(params.file)) do
        if test.name == params.test then
            local ok, err = run(test)
            return { ok = ok, error = err }
        end
    end
    return { ok = false, error = "no test named " .. params.test }
end

uji.schedule(function()
    require("uji.core.app").session.directory = params.root .. "/work"
    local ok, result = xpcall(params.mode == "list" and listed or ran, trace)
    if not ok then
        result = { ok = false, error = result }
    end
    sys.sleep(0)
    write(params.out, sys.json.encode(result))
    require("uji.core.ui"):quit()
end)
