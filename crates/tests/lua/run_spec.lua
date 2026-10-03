local process = require("uji.core.system.process")
local sandbox = require("support.sandbox")
local server = require("support.server")
local sys = require("uji.sys")

local CONFIG = [[
uji.provider.add({
    id = "test",
    name = "Test",
    api = uji.api.openai(),
    base_url = %q,
    models = { { id = "m", context = 100000, output = 1000 } },
})
require("uji.core.model").set_setting("llm.provider", "test")
require("uji.core.model").set_setting("llm.model", "m")
%s
]]

local function configure(dir, mock, extra)
    sandbox.write(dir.cfg .. "/init.lua", string.format(CONFIG, mock.url .. "/v1", extra or ""))
end

local function prepare(mock)
    local dir = sandbox.dir("run")
    sandbox.write(dir.work .. "/notes.txt", "alpha\nline two\ngamma\n")
    configure(dir, mock)
    return dir
end

local function uji_run(dir, args)
    local argv = { sandbox.bin, "run", "--config-dir", dir.cfg, "--data-dir", dir.data, "--db", dir.db }
    for _, arg in ipairs(args) do
        argv[#argv + 1] = arg
    end
    local output = { stdout = {}, stderr = {} }
    local result = assert(process.run({ argv = argv, cwd = dir.work }, function(stream, line)
        output[stream][#output[stream] + 1] = line
    end))
    output.code = result.code
    return output
end

local function events(output)
    local out = {}
    for _, line in ipairs(output.stdout) do
        local ok, event = pcall(sys.json.decode, line, { nulls = false })
        if ok then
            out[#out + 1] = event
        end
    end
    return out
end

local function kinds(seen)
    local out = {}
    for index, event in ipairs(seen) do
        out[index] = event.type == "message" and "message:" .. event.message.type or event.type
    end
    return out
end

local function tool_contents(seen)
    local out = {}
    for _, event in ipairs(seen) do
        if event.message and event.message.type == "tool" then
            out[#out + 1] = event.message.content
        end
    end
    return out
end

local function answered(request)
    for _, message in ipairs(request.body.messages or {}) do
        if message.role == "tool" then
            return true
        end
    end
    return false
end

local function after(calls)
    return server.start(function(request)
        if answered(request) then
            return server.text("finished")
        end
        return server.tool_calls(0, calls)
    end)
end

local function replying(text)
    return server.start(function()
        return server.text(text)
    end)
end

it("prints the answer and exits", function()
    local mock = replying("hello there")
    local output = uji_run(prepare(mock), { "say", "hi" })
    assert.equal(0, output.code)
    assert.same({ "hello there" }, output.stdout)
    assert.equal("say hi", mock:turns()[1].body.messages[2].content)
end)

it("prints each message as JSON and ends with done", function()
    local mock = after({ { "read_file", '{"path":"notes.txt"}' } })
    local output = uji_run(prepare(mock), { "--json", "read the notes" })
    assert.equal(0, output.code)
    local seen = events(output)
    assert.same({
        "session",
        "message:user",
        "message:assistant",
        "message:tool",
        "message:assistant",
        "done",
    }, kinds(seen))
    assert.truthy(tool_contents(seen)[1]:find("line two", 1, true))
    local done = seen[#seen]
    assert.equal("finished", done.text)
    assert.is_true(done.usage.input > 0)
end)

it("takes its model, tools and prompt from flags", function()
    local mock = replying("ok")
    local output = uji_run(prepare(mock), {
        "--model",
        "test/m2",
        "--tools",
        "read_file",
        "--append-prompt",
        "You check files.",
        "check",
    })
    assert.equal(0, output.code)
    local sent = mock:turns()[1]
    assert.equal("m2", sent.body.model)
    local tools = {}
    for _, tool in ipairs(sent.body.tools) do
        tools[#tools + 1] = tool["function"].name
    end
    assert.same({ "read_file" }, tools)
    local suffix = "\n\nYou check files."
    assert.equal(suffix, server.system(sent):sub(-#suffix))
end)

it("allows what would ask and keeps denials", function()
    local mock = after({ { "run_command", '{"command":"echo hi"}' } })
    local dir = prepare(mock)
    local allowed = events(uji_run(dir, { "--json", "say hi" }))
    assert.truthy(tool_contents(allowed)[1]:find("hi", 1, true))
    configure(dir, mock, 'uji.tool.policy({ run_command = { deny = { "echo *" } } })')
    local denied = events(uji_run(dir, { "--json", "say hi" }))
    assert.same({ "denied: denied by policy" }, tool_contents(denied))
end)

it("saves its session under a parent", function()
    local mock = replying("ok")
    local dir = prepare(mock)
    local parent = events(uji_run(dir, { "--json", "start" }))[1].id
    local child = uji_run(dir, { "--parent", parent, "--title", "find the parser", "look" })
    assert.equal(0, child.code)
    local missing = uji_run(dir, { "--parent", "00000000-0000-0000-0000-000000000000", "look" })
    assert.equal(1, missing.code)
    assert.truthy(table.concat(missing.stderr, "\n"):find("no session with id", 1, true))
    local db = assert(sys.db.open(dir.db))
    assert.same({ { title = "find the parser", parent = parent } }, db:query("SELECT title, parent FROM sessions WHERE parent IS NOT NULL"))
    db:close()
end)

it("reports a failed turn and exits with one", function()
    local mock = server.start(function()
        return server.status(400, '{"error":{"message":"bad request"}}')
    end)
    local dir = prepare(mock)
    local output = uji_run(dir, { "--json", "hello" })
    assert.equal(1, output.code)
    local seen = events(output)
    local done = seen[#seen]
    assert.equal("done", done.type)
    assert.truthy(done.error:find("bad request", 1, true))
    local plain = uji_run(dir, { "hello" })
    assert.equal(1, plain.code)
    assert.equal("uji: error:", table.concat(plain.stderr, "\n"):sub(1, 11))
end)

it("reports headless failure even when its error message cannot be saved", function()
    local dir = sandbox.dir("rejected-error")
    sandbox.write(
        dir.cfg .. "/init.lua",
        [=[
uji.provider.add({
    id = "failure-fixture",
    name = "Fixture",
    base_url = "https://fixture.invalid",
    models = { { id = "m", context = 100000, output = 1000 } },
    api = {
        stream = function(_, _, reply)
            reply.fail({ kind = "provider", message = "fixture failure" })
        end,
    },
})
require("uji.core.model").set_setting("llm.provider", "failure-fixture")
require("uji.core.model").set_setting("llm.model", "m")
require("uji.core.app").store.db:exec([[CREATE TRIGGER IF NOT EXISTS reject_error
    BEFORE INSERT ON messages WHEN NEW.type='error'
    BEGIN SELECT RAISE(ABORT,'error write rejected'); END]])
]=]
    )
    local output = uji_run(dir, { "--json", "the original prompt" })
    assert.equal(1, output.code)
    local seen, completed = events(output), 0
    for _, entry in ipairs(seen) do
        if entry.type == "done" then
            completed = completed + 1
            assert.truthy(entry.error:find("fixture failure", 1, true))
            assert.is_nil(entry.text)
        elseif entry.type == "message" then
            assert.equal("user", entry.message.type)
        end
    end
    assert.equal(1, completed)
    local plain = uji_run(dir, { "the original prompt" })
    assert.equal(1, plain.code)
    assert.same({}, plain.stdout)
    assert.truthy(table.concat(plain.stderr, "\n"):find("fixture failure", 1, true))
    local db = assert(sys.db.open(dir.db))
    assert.same({ { type = "user" }, { type = "user" } }, db:query("SELECT type FROM messages ORDER BY seq"))
    db:close()
end)

it("knows its program and arguments", function()
    assert.is_string(uji.os.executable)
    assert.equal("new", uji.os.argv[2])
end)
