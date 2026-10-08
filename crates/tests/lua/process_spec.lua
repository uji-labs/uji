local process = require("uji.core.system.process")
local sandbox = require("support.sandbox")
local sys = require("uji.sys")

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

it("gives a job's standard output alone to on_stdout when nothing takes its errors", function()
    local out, exited = {}, sys.promise()
    local job = process.start({
        shell = "echo one; echo two 1>&2",
        on_stdout = function(line)
            out[#out + 1] = line
        end,
        on_exit = function(code)
            exited:resolve(code)
        end,
    })
    job.close()
    assert.equal(0, exited:await())
    assert.same({ "one" }, out)
end)

it("runs a string through the shell with its quotes intact and a list as it is", function()
    local lines = {}
    local function keep(_, line)
        lines[#lines + 1] = line
    end
    process.run(process.command('printf "%s|" "a b" \'c\''), keep)
    process.run(process.command({ "printf", "%s|", "a b", "c" }), keep)
    assert.same({ "a b|c|", "a b|c|" }, lines)
end)

local function captured(opts, shell)
    local capture = process.Capture(opts)
    process.run({ shell = shell }, function(_, line)
        capture:push(line)
    end)
    return capture:finish()
end

local HUNDRED = "for i in $(seq 1 100); do echo line-$i; done"

it("keeps the end of a long output within the byte limit", function()
    local text = captured({ bytes = 40 }, HUNDRED)
    local kept = "line-96\nline-97\nline-98\nline-99\nline-100\n\n[Showing lines 96-100 of 100 (40B limit). Full output: "
    assert.equal(kept, text:sub(1, #kept))
end)

it("keeps the end of a long output within the line limit", function()
    local text = captured({ lines = 3 }, HUNDRED)
    local kept = "line-98\nline-99\nline-100\n\n[Showing lines 98-100 of 100. Full output: "
    assert.equal(kept, text:sub(1, #kept))
end)

it("keeps the end of a last line longer than the byte limit", function()
    local text = captured({ bytes = 40 }, "echo first; printf start; head -c 100 /dev/zero | tr '\\0' x; printf end")
    local kept = string.rep("x", 37) .. "end\n\n[Showing last 40B of line 2 (line is 108B). Full output: "
    assert.equal(kept, text:sub(1, #kept))
end)

it("leaves a short output alone", function()
    assert.equal("line-1\nline-2", captured({}, "echo line-1; echo line-2"))
end)

it("saves the full output once it cuts", function()
    local path = sandbox.root .. "/spill.log"
    assert.truthy(captured({ bytes = 40, spill = path }, HUNDRED):find(path, 1, true))
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
