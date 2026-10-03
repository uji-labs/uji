local agent = require("support.agent")
local sandbox = require("support.sandbox")
local server = require("support.server")
local sys = require("uji.sys")

local function counted(from, to)
    local out = {}
    for n = from, to do
        out[#out + 1] = tostring(n)
    end
    return out
end

local function numbered(lines, from)
    local out = {}
    for at, line in ipairs(lines) do
        out[at] = string.format("%5d| %s", at + from - 1, line)
    end
    return table.concat(out, "\n") .. "\n"
end

local function slice(list, from, to)
    return { unpack(list, from, to) }
end

local function round_trip(calls)
    local round = 0
    local mock = server.start(function(request)
        if server.has_tools(request) then
            round = round + 1
            if round == 1 then
                return server.tool_calls(0, calls)
            end
        end
        return server.text("done")
    end)
    sandbox.file("notes.txt", "alpha\nline two\ngamma\ndelta\nepsilon\n")
    sandbox.file("big.txt", table.concat(counted(1, 3000), "\n") .. "\n")
    sandbox.file("long.txt", string.rep("x", 5000) .. "\n")
    sandbox.file("empty.txt", "")
    sandbox.file("bin.dat", "ab\0cd")
    sandbox.write(sandbox.root .. "/outside.txt", "outside")
    agent.allow_all()
    local messages = agent.run({ url = mock.url })
    return agent.tool_results(messages), mock
end

it("sends the model tool specs that match the built in tools", { timeout = 20 }, function()
    local _, mock = round_trip({})
    local expected = sys.json.decode(sandbox.read(sandbox.fixtures .. "/tool_specs.json"), { nulls = false })
    assert.same(expected, mock:turns()[1].body.tools)
end)

it("pages numbered lines from read_file and refuses what it cannot read", { timeout = 20 }, function()
    local results = round_trip({
        { "read_file", '{"path": "notes.txt"}' },
        { "read_file", '{"path": "notes.txt", "offset": 3, "limit": 2}' },
        { "read_file", '{"path": "notes.txt", "offset": 99}' },
        { "read_file", '{"path": "."}' },
        { "read_file", '{"path": "missing.txt"}' },
        { "read_file", '{"path": "bin.dat"}' },
        { "read_file", '{"path": "big.txt"}' },
        { "read_file", '{"path": "big.txt", "offset": 2990}' },
        { "read_file", '{"path": "long.txt"}' },
        { "read_file", '{"path": "empty.txt"}' },
        { "read_file", '{"path": "../outside.txt"}' },
        { "read_file", '{"path": ""}' },
    })
    local notes = { "alpha", "line two", "gamma", "delta", "epsilon" }
    local long = string.rep("x", 2000) .. " \226\128\166[line truncated]"
    assert.same({
        numbered(notes, 1),
        numbered(slice(notes, 3, 4), 3) .. "\n[showed lines 3-4 of 5; continue with offset 5]",
        "error: offset 99 is past the end of notes.txt (5 lines)",
        "error: . is a directory, not a file",
        "error: read missing.txt: No such file or directory (os error 2)",
        "error: bin.dat looks like a binary file",
        numbered(counted(1, 2000), 1) .. "\n[showed lines 1-2000 of 3000; continue with offset 2001]",
        numbered(counted(2990, 3000), 2990),
        numbered({ long }, 1),
        "empty.txt is empty",
        "error: ../outside.txt is outside the working directory (" .. sandbox.work .. "); tools can only reach files under it",
        "error: `path` is required and must be a non-empty string",
    }, results)
end)

it("replaces exact snippets with edit_file and explains what it could not do", { timeout = 20 }, function()
    local results = round_trip({
        { "edit_file", '{"path": "notes.txt", "old_string": "gamma", "new_string": "GAMMA"}' },
        { "edit_file", '{"path": "notes.txt", "old_string": "line two", "new_string": "LINE TWO"}' },
        { "edit_file", '{"path": "notes.txt", "old_string": "nope", "new_string": "x"}' },
        { "edit_file", '{"path": "notes.txt", "old_string": "o", "new_string": "0"}' },
        { "edit_file", '{"path": "notes.txt", "old_string": "e", "new_string": "E", "replace_all": true}' },
        { "edit_file", '{"path": "notes.txt", "old_string": "same", "new_string": "same"}' },
        { "edit_file", '{"path": "notes.txt", "new_string": "x"}' },
        { "edit_file", '{"path": "missing.txt", "old_string": "a", "new_string": "b"}' },
    })
    assert.same({
        "edited notes.txt at line 3",
        "edited notes.txt at line 2",
        "error: old_string was not found in notes.txt. Read the file again and copy the snippet exactly, without line-number prefixes.",
        "edited notes.txt at line 5",
        "edited notes.txt: replaced 2 occurrences",
        "error: old_string and new_string are identical",
        "error: `old_string` is required and must be a non-empty string",
        "error: read missing.txt: No such file or directory (os error 2)",
    }, results)
    assert.equal("alpha\nLINE TWO\nGAMMA\ndElta\nEpsil0n\n", sandbox.read(sandbox.work .. "/notes.txt"))
end)

it("creates directories with write_file and reports what it wrote", { timeout = 20 }, function()
    local results = round_trip({
        { "write_file", '{"path": "made/deep/new.txt", "content": "one\\ntwo\\n"}' },
        { "write_file", '{"path": "notes.txt", "content": "replaced"}' },
        { "write_file", '{"path": "blank.txt", "content": ""}' },
    })
    assert.same({
        "created made/deep/new.txt (2 lines)",
        "overwrote notes.txt (1 lines)",
        "created blank.txt (0 lines)",
    }, results)
    assert.equal("one\ntwo\n", sandbox.read(sandbox.work .. "/made/deep/new.txt"))
    assert.equal("replaced", sandbox.read(sandbox.work .. "/notes.txt"))
    assert.equal("", sandbox.read(sandbox.work .. "/blank.txt"))
end)

it("reports output, exit codes and timeouts from run_command", { timeout = 20 }, function()
    local results = round_trip({
        { "run_command", '{"command": "echo hi; sleep 0.1; echo err >&2"}' },
        { "run_command", '{"command": "echo partial; exit 3"}' },
        { "run_command", '{"command": "true"}' },
        { "run_command", '{"command": "exit 4"}' },
        { "run_command", '{"command": "seq 1 8000"}' },
        { "run_command", '{"command": "pwd"}' },
        { "run_command", '{"command": "sleep 5", "timeout": 1}' },
        { "run_command", '{"command": ""}' },
    })
    assert.equal(8, #results)
    local both, partial, quiet, failed, long, pwd, slow, empty = unpack(results)
    assert.equal("hi\nerr", both)
    assert.equal("partial\n(exit code 3)", partial)
    assert.equal("(no output, exit code 0)", quiet)
    assert.equal("(exit code 4)", failed)
    local dropped = "\226\128\166 3200 earlier lines dropped; full output in "
    assert.equal(dropped, long:sub(1, #dropped))
    assert.equal("\n7999\n8000", long:sub(-10))
    assert.equal(sys.fs.realpath(sandbox.work), sys.fs.realpath(pwd))
    assert.equal("error: command timed out after 1s", slow)
    assert.equal("error: `command` is required and must be a non-empty string", empty)
end)
