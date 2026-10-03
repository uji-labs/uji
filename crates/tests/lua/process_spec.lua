local process = require("uji.core.system.process")
local sandbox = require("support.sandbox")

local function ignore() end

local function outcome(result)
    if result.timed_out then
        return { "timed_out" }
    end
    return { "code", result.code }
end

it("gives back both streams and the exit code", function()
    local out, err = {}, {}
    local result = process.run({ shell = "echo one; echo two 1>&2; exit 7" }, function(stream, line)
        if stream == "stdout" then
            out[#out + 1] = line
        else
            err[#err + 1] = line
        end
    end)
    assert.same({ "code", 7 }, outcome(result))
    assert.same({ "one" }, out)
    assert.same({ "two" }, err)
end)

it("keeps the end of a long output", function()
    local capture = process.Capture(40)
    process.run({ shell = "for i in $(seq 1 100); do echo line-$i; done" }, function(_, line)
        capture:push(line)
    end)
    local text = capture:finish()
    assert.equal("line-100", text:sub(-8))
    assert.is_nil(text:find("line-1\n", 1, true), "kept the start instead of the end")
    assert.truthy(text:find("earlier lines dropped", 1, true))
end)

it("spills what the window drops", function()
    local path = sandbox.root .. "/spill.log"
    local capture = process.Capture(40, path)
    process.run({ shell = "for i in $(seq 1 100); do echo line-$i; done" }, function(_, line)
        capture:push(line)
    end)
    assert.truthy(capture:finish():find(path, 1, true))
    local spilled = sandbox.lines(path)
    assert.equal(100, #spilled)
    assert.equal("line-1", spilled[1])
    assert.equal("line-100", spilled[100])
end)

it("kills the command when it times out", function()
    local started = uji.os.clock()
    assert.same({ "timed_out" }, outcome(process.run({ shell = "sleep 30", timeout = 0.2 }, ignore)))
    assert.is_true(uji.os.clock() - started < 5)
end)

it("kills the command when it is cancelled", function()
    local started = uji.os.clock()
    local pid
    local worker = uji.task.spawn(function()
        local proc = process.spawn({ shell = "sleep 30" })
        pid = proc.pid
        proc:wait()
    end)
    uji.sleep(0.1)
    worker:cancel()
    uji.sleep(0.2)
    local alive = process.run({ argv = { "kill", "-0", tostring(pid) } }, ignore)
    assert.are_not.equal(0, alive.code)
    assert.is_true(uji.os.clock() - started < 5)
end)

it("ends the input of a command that reads with no writer", function()
    assert.same({ "code", 0 }, outcome(process.run({ shell = "cat" }, ignore)))
end)

it("passes what is written to the command", function()
    local proc = process.spawn({ argv = { "cat" }, stdin = true })
    proc:write("fed\n")
    proc:close()
    local lines = {}
    for line in proc:lines() do
        lines[#lines + 1] = line
    end
    assert.equal(0, proc:wait().code)
    assert.same({ "fed" }, lines)
end)

it("gives an error rather than an exit code for a program that is not there", function()
    assert.is_nil(process.run({ argv = { "definitely-not-a-program" } }, ignore))
    assert.is_nil(process.run({ argv = {} }, ignore))
end)
