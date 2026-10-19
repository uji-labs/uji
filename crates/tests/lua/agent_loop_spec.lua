local agent = require("support.agent")
local app = require("uji.core.app")
local sandbox = require("support.sandbox")
local screen = require("support.ui")
local server = require("support.server")
local sys = require("uji.sys")
local ui = require("uji.core.ui")
local wait = require("support.wait")

local function run(url, opts)
    sandbox.file("notes.txt", "alpha\nline two\ngamma\n")
    opts = opts or {}
    opts.url = url
    return agent.run(opts)
end

local function read_notes()
    return server.tool_calls(0, { { "read_file", '{"path":"notes.txt"}' } })
end

local function compacted(mock)
    for _, request in ipairs(mock.requests) do
        if server.system(request):find("You compact coding sessions", 1, true) == 1 then
            return true
        end
    end
    return false
end

-- A model that takes its time over the summary, so a test can look at uji
-- while the compaction is in flight.
local function summarising(seconds)
    local mock = agent.serve(function()
        return server.text("done")
    end, { summary = seconds or 0.5 })
    agent.provider(mock.url, 4000)
    uji.model.use({ provider = "test", model = "m" })
    return mock
end

local function seeded()
    for turn = 0, 5 do
        app.session:append({ type = "user", text = "question " .. turn })
        app.session:append({ type = "assistant", text = string.rep("answer ", 400) })
    end
end

it("retries a failed request until it succeeds", function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.status(500, "boom")
        elseif round == 1 then
            return server.status(429, '{"error":"slow"}', { { "retry-after", "1" } })
        elseif round == 2 then
            return read_notes()
        end
        return server.text("done")
    end)
    agent.allow_all()
    local notices = {}
    uji.on("notice", function(notice)
        notices[#notices + 1] = notice.text
    end)
    local messages = run(mock.url)
    assert.equal(4, #mock:turns())
    assert.equal(1, notices[1]:find("request failed (http: 500: boom), retrying in ", 1, true))
    assert.equal('request failed (http: 429: {"error":"slow"}), retrying in 1s (2/5)', notices[2])
    assert.same({ "    1| alpha\n    2| line two\n    3| gamma\n" }, agent.tool_results(messages))
    assert.equal("done", agent.last_answer(messages))
end)

it("answers malformed arguments and unknown tools without running them", { timeout = 10 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, {
                { "read_file", "[1,2]" },
                { "read_file", "null" },
                { "read_file", '"s"' },
                { "read_file", "" },
                { "read_file", " 7 " },
                { "nope", "{}" },
            })
        end
        return server.text("ok")
    end)
    agent.allow_all()
    local function shape(kind)
        return "error: arguments must be a JSON object, got " .. kind .. ". Send a single object matching the tool schema."
    end
    assert.same({
        shape("an array"),
        shape("null"),
        shape("a string"),
        "error: `path` is required and must be a non-empty string",
        shape("a number"),
        "error: unknown tool `nope`. Available tools: ask_user, docs, edit_file, job_output, read_file, run_command, stop_job, write_file.",
    }, agent.tool_results(run(mock.url)))
end)

it("answers arguments that are not JSON instead of ending the turn", { timeout = 10 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, { { "read_file", '{"path": "notes.txt"' } })
        end
        return server.text("ok")
    end)
    agent.allow_all()
    local messages = run(mock.url)
    local problem = agent.tool_results(messages)[1]
    assert.is_true(problem:find("error: arguments are not valid JSON", 1, true) ~= nil, problem)
    assert.equal("ok", agent.last_answer(messages))
end)

it("runs a call whose arguments carry a stray closing character", { timeout = 10 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, { { "read_file", '{"path":"notes.txt"}}' } })
        end
        return server.text("ok")
    end)
    agent.allow_all()
    local messages = run(mock.url)
    assert.same({ "    1| alpha\n    2| line two\n    3| gamma\n" }, agent.tool_results(messages))
    assert.equal("ok", agent.last_answer(messages))
end)

it("reports a reply the output limit cut off", { timeout = 10 }, function()
    local mock = agent.serve(function()
        return server.tool_calls(0, { { "read_file", '{"path": "notes.txt"' } }, "length")
    end)
    agent.allow_all()
    local messages = run(mock.url)
    local last = messages[#messages]
    assert.equal("error", last.type)
    assert.is_true(last.text:find("cut off while calling `read_file`", 1, true) ~= nil, last.text)
end)

it("steers a turn with a message sent during it", { timeout = 15 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, { { "run_command", '{"command":"sleep 1"}' } })
        end
        return server.text("done")
    end)
    agent.allow_all()
    uji.on("tool_started", function()
        uji.session.submit("extra")
    end)
    local messages = run(mock.url)
    local turns = mock:turns()
    assert.equal(2, #turns)
    local sent = turns[2].body.messages
    assert.equal("user", sent[#sent].role)
    assert.equal("extra", sent[#sent].content)
    local steered = false
    for _, message in ipairs(messages) do
        steered = steered or (message.type == "user" and message.text == "extra")
    end
    assert.is_true(steered)
    assert.equal("done", agent.last_answer(messages))
end)

it("allows one call and denies the next with the approval keys", { timeout = 15 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, {
                { "edit_file", '{"path":"notes.txt","old_string":"alpha","new_string":"ALPHA"}' },
                { "write_file", '{"path":"x.txt","content":"x"}' },
            })
        end
        return server.text("done")
    end)
    local messages = run(mock.url, { answers = { "y", "n" } })
    assert.same({ "edited notes.txt at line 1", "denied: user denied" }, agent.tool_results(messages))
    assert.equal("done", agent.last_answer(messages))
end)

it("compacts a turn that outgrows its window mid turn", { timeout = 20 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, { { "run_command", '{"command":"yes a long line of command output | head -n 2000"}' } })
        end
        return server.text("done")
    end)
    agent.allow_all()
    local messages = run(mock.url, { context = 4000 })
    assert.is_true(compacted(mock))
    local turns = mock:turns()
    assert.equal(2, #turns)
    local folded = turns[2].body.messages[2].content
    assert.equal(1, folded:find("Summary of the earlier part of this conversation:", 1, true))
    assert.truthy(folded:find("SUMMARY OF EARLIER WORK", 1, true))
    assert.equal("done", agent.last_answer(messages))
end)

it("keeps calling tools until the model answers", { timeout = 90 }, function()
    local mock = agent.serve(function(round)
        if round < 150 then
            return read_notes()
        end
        return server.text("done")
    end)
    agent.allow_all()
    local messages = run(mock.url)
    assert.equal(151, #mock:turns())
    assert.equal("done", agent.last_answer(messages))
end)

it("gives a tool call without an id one", { timeout = 10 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.events({
                {
                    choices = {
                        {
                            index = 0,
                            delta = {
                                tool_calls = {
                                    {
                                        index = 0,
                                        type = "function",
                                        ["function"] = { name = "read_file", arguments = '{"path":"notes.txt"}' },
                                    },
                                },
                            },
                            finish_reason = uji.json.null,
                        },
                    },
                },
                { choices = { { index = 0, delta = {}, finish_reason = "tool_calls" } } },
            })
        end
        return server.text("done")
    end)
    agent.allow_all()
    local called, answered
    for _, message in ipairs(run(mock.url)) do
        if message.type == "assistant" and message.tool_calls and message.tool_calls[1] and not called then
            called = message.tool_calls[1].id
        elseif message.type == "tool" and not answered then
            answered = message.tool_call_id
        end
    end
    assert.equal("call_", called:sub(1, 5))
    assert.is_true(#called > 5)
    assert.equal(called, answered)
end)

it("ends the turn when a running tool is interrupted", { timeout = 20 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, { { "run_command", '{"command":"sleep 30"}' } })
        end
        return server.text("done")
    end)
    agent.allow_all()
    uji.on("tool_started", function()
        uji.defer(0.5, uji.session.interrupt)
    end)
    local started = uji.os.clock()
    local messages = run(mock.url)
    assert.is_true(uji.os.clock() - started < 10)
    assert.same({ "error: interrupted by the user while this tool ran" }, agent.tool_results(messages))
    assert.equal("interrupted", agent.last_error(messages))
    assert.equal(1, #mock:turns())
end)

it("sends the queued message once the turn is interrupted", { timeout = 20 }, function()
    local mock = agent.serve(function(round)
        if round == 0 then
            return server.tool_calls(0, { { "run_command", '{"command":"sleep 30"}' } })
        end
        return server.text("done")
    end)
    agent.allow_all()
    uji.on("tool_started", function()
        uji.session.submit("instead")
        uji.defer(0.5, uji.session.interrupt)
    end)
    local messages = run(mock.url)
    local types = {}
    for index, message in ipairs(messages) do
        types[index] = message.type == "user" and message.text or message.type
    end
    assert.same({ "go", "assistant", "tool", "error", "instead", "assistant" }, types)
    local turns = mock:turns()
    assert.equal(2, #turns)
    local sent = turns[2].body.messages
    assert.equal("instead", sent[#sent].content)
    assert.equal("done", agent.last_answer(messages))
end)

it("drops the connection when a stream is interrupted", { timeout = 20 }, function()
    local mock = agent.serve(function()
        return server.drip('data: {"choices":[{"index":0,"delta":{"content":"."}}]}', 0.2)
    end)
    uji.defer(1, uji.session.interrupt)
    local messages = run(mock.url)
    assert.equal("interrupted", agent.last_error(messages))
    local waited = uji.os.clock()
    while mock.dropped == 0 and uji.os.clock() - waited < 3 do
        uji.sleep(0.05)
    end
    assert.equal(1, mock.dropped)
end)

it("gives up on and retries a stream that only sends keepalives", { timeout = 6 }, function()
    local mock = agent.serve(function()
        return server.drip('data: {"choices":[{"index":0,"delta":{}}]}', 0.2)
    end)
    uji.api.stream.idle = 1
    sandbox.file("notes.txt", "alpha\nline two\ngamma\n")
    agent.provider(mock.url, 100000)
    uji.model.use({ provider = "test", model = "m" })
    uji.session.submit("go")
    local waited = uji.os.clock()
    while #mock:turns() < 2 and uji.os.clock() - waited < 5 do
        uji.sleep(0.05)
    end
    assert.is_true(#mock:turns() >= 2)
end)

it("sends a message that waits for compaction once it is done", { timeout = 20 }, function()
    local mock = agent.serve(function()
        return server.text("done")
    end)
    local history = {}
    for turn = 0, 5 do
        history[#history + 1] = { type = "user", text = "question " .. turn }
        history[#history + 1] = { type = "assistant", text = string.rep("answer ", 400) }
    end
    local messages = agent.run({ url = mock.url, context = 4000, history = history })
    assert.is_true(compacted(mock))
    local turns = mock:turns()
    assert.equal(1, #turns)
    local sent = turns[1].body.messages
    assert.equal("go", sent[#sent].content)
    assert.equal("done", agent.last_answer(messages))
end)

it("compacts a conversation that no longer leaves room for its reply", { timeout = 20 }, function()
    local mock = agent.serve(function()
        return server.text("done")
    end)
    agent.provider(mock.url, 3000)
    uji.model.use({ provider = "test", model = "m" })
    local gate = 3000 - 1000
    while app.session:used_tokens() < gate + 50 do
        app.session:append({ type = "user", text = "question" })
        app.session:append({ type = "assistant", text = string.rep("answer ", 40) })
    end
    assert.is_true(app.session:used_tokens() < 3000 - math.floor(3000 / 4), "the history should fit the reply it asks for")
    uji.session.submit("go")
    wait.eventually(function()
        return not app.agent:working()
    end)
    assert.is_true(compacted(mock))
end)

it("asks for no more reply than the window has left", { timeout = 20 }, function()
    local mock = agent.serve(function()
        return server.text("done")
    end)
    uji.provider.add({
        id = "test",
        name = "Test",
        api = uji.api.responses(),
        base_url = mock.url .. "/v1",
        models = { { id = "m", context = 1100, output = 1000 } },
    })
    uji.model.use({ provider = "test", model = "m" })
    app.session:append({ type = "user", text = string.rep("filler ", 200) })
    require("uji.core.task").spawn_in({ session = app.session }, function()
        require("uji.core.model").generate({ messages = { { type = "user", text = "hi" } } })
    end)
    wait.eventually(function()
        return #mock.requests > 0
    end)
    assert.is_true(mock.requests[1].body.max_output_tokens < 1000)
end)

it("tells how much of the window the conversation may use", function()
    local mock = agent.serve(function()
        return server.text("done")
    end)
    agent.provider(mock.url, 10000)
    uji.model.use({ provider = "test", model = "m" })
    assert.equal(10000, uji.session.context().window)
    assert.equal(9000, uji.session.context().usable)
end)

it("reports the context the provider counted", { timeout = 10 }, function()
    local mock = agent.serve(function()
        return server.text("done")
    end)
    agent.run({ url = mock.url })
    assert.equal(12, uji.session.context().used)
end)

it("shows the compaction while the summary is written, and stops it on esc", { timeout = 20 }, function()
    summarising()
    seeded()
    uji.session.submit("go")
    wait.eventually(function()
        return app.agent:compacting()
    end)
    assert.is_true(app.agent.compaction.messages > 0, "the compaction says how many messages it folds")
    assert.truthy(table.concat(screen.rows(true)):find("Compacting the conversation", 1, true))
    assert.is_true(app.agent:interrupt())
    assert.is_nil(app.agent.compaction)
    wait.eventually(function()
        return not app.agent:working()
    end)
    for _, message in ipairs(app.session:messages()) do
        assert.is_not_equal("compaction", message.type)
    end
end)

it("moves the spinner while the summary is written", { timeout = 20 }, function()
    summarising(2)
    seeded()
    uji.session.submit("go")
    wait.eventually(function()
        return app.agent:compacting()
    end)
    local function line()
        for _, row in ipairs(screen.rows(true)) do
            if row:find("Compacting the conversation", 1, true) then
                return row
            end
        end
    end
    local first = assert(line(), "the compaction line is not on screen")
    sys.sleep(0.25)
    assert.is_not_equal(first, line(), "the compaction line never moved")
end)

it("shows the compaction a turn folds on its own", { timeout = 20 }, function()
    summarising()
    seeded()
    local messages = require("uji.core.agent.view").build(app.session:entries())
    uji.task.spawn(function()
        app.agent:fold(messages)
    end)
    wait.eventually(function()
        return app.agent:compacting()
    end)
    assert.is_true(app.agent.compaction.messages > 0, "a fold says how many messages it folds")
    wait.eventually(function()
        return not app.agent:compacting()
    end)
end)

it("does not remember a stopped manual compaction", { timeout = 20 }, function()
    summarising()
    seeded()
    assert.is_true(app.agent:compact())
    wait.eventually(function()
        return app.agent:compacting()
    end)
    assert.is_true(app.agent:interrupt())
    assert.is_nil(app.agent.compaction)
    assert.is_falsy(app.agent.skipped_compaction)
end)

it("brings the compacted marker into view", { size = { 80, 12 }, timeout = 20 }, function()
    summarising()
    seeded()
    app.agent:compact()
    ui.scroll:scroll(-20)
    wait.eventually(function()
        return not app.agent:working()
    end)
    local rule = ui.theme.tokens.symbols.rule
    local found
    for _, row in ipairs(screen.rows()) do
        if row:find("compacted", 1, true) and row:find(rule, 1, true) then
            found = row
            break
        end
    end
    assert.truthy(found, "the marker is on screen")
end)

describe("a plugin", function()
    local function echo()
        return agent.serve(function(round)
            if round == 0 then
                return server.tool_calls(0, { { "run_command", '{"command":"echo hi"}' } })
            end
            return server.text("done")
        end)
    end

    local function answering(allow)
        uji.ui.confirm = function(request)
            return request.body:find("echo hi", 1, true) ~= nil and allow
        end
    end

    it("allows a call by answering the approval question", { timeout = 10 }, function()
        answering(true)
        local results = agent.tool_results(run(echo().url))
        assert.truthy(results[1]:find("hi", 1, true))
    end)

    it("denies a call by answering the approval question", { timeout = 10 }, function()
        answering(false)
        assert.same({ "denied: user denied" }, agent.tool_results(run(echo().url)))
    end)
end)
