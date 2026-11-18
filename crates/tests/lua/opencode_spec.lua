local agent = require("support.agent")
local app = require("uji.core.app")
local catalog = require("uji.core.catalog")
local list = require("uji.utils.list")
local server = require("support.server")
local sys = require("uji.sys")

local METADATA = "https://models.dev/api.json"

local function metadata(models)
    local request = uji.http.request
    uji.http.request = function(opts, ...)
        if opts.url == METADATA then
            return { status = 200, headers = {}, body = uji.json.encode({ opencode = { models = models } }) }
        end
        return request(opts, ...)
    end
end

local function inventory(ids, reply)
    return server.start(function(request)
        if request.path == "/v1/models" then
            local data = {}
            for index, id in ipairs(ids) do
                data[index] = { id = id, object = "model" }
            end
            return server.status(200, uji.json.encode({ object = "list", data = data }))
        end
        return reply and reply(request) or server.status(500, "recorded")
    end)
end

local function register(mock)
    require("uji.builtin.opencode")({
        id = "opencode-test",
        name = "OpenCode Test",
        base_url = mock.url .. "/v1",
        source = "opencode",
    })
    return catalog.get("opencode-test")
end

local function find(rows, id)
    for _, row in ipairs(rows) do
        if row.id == id then
            return row
        end
    end
end

it("does not load models for a provider nobody has picked", function()
    assert.equal(uji.provider.STATE.IDLE, uji.provider.get("opencode-go").state)
    assert.equal(uji.provider.STATE.IDLE, uji.provider.get("opencode-zen").state)
end)

it("lists the live models with their limits, efforts and images", function()
    metadata({
        ["gpt-x"] = {
            limit = { context = 400000, output = 128000 },
            reasoning = true,
            reasoning_options = { { type = "effort", values = { "none", "low", "high", "ultra" } } },
            modalities = { input = { "text", "image" } },
            cost = { input = 1, output = 2, cache_read = 0.1 },
            provider = { npm = "@ai-sdk/openai" },
        },
        ["glm-x"] = { limit = { context = 200000 }, modalities = { input = { "text" } } },
    })
    local mock = inventory({ "gpt-x", "glm-x", "gpt-x", "unlisted" })
    register(mock)
    local rows = uji.provider.load("opencode-test").models
    local ids = {}
    for index, row in ipairs(rows) do
        ids[index] = row.id
    end
    assert.same({ "glm-x", "gpt-x", "unlisted" }, ids)
    local gpt = find(rows, "gpt-x")
    assert.equal(400000, gpt.context)
    assert.equal(128000, gpt.output)
    assert.is_true(gpt.reasoning)
    assert.is_true(gpt.images)
    assert.is_true(gpt.cache)
    assert.same({ "off", "low", "high" }, gpt.efforts)
    local glm = find(rows, "glm-x")
    assert.equal(200000, glm.context)
    assert.is_nil(glm.output)
    assert.is_false(glm.images)
    assert.same({ id = "unlisted", reasoning = false, cache = false }, find(rows, "unlisted"))
end)

it("sends each model to the API that models.dev names for it", function()
    metadata({
        ["gpt-x"] = { provider = { npm = "@ai-sdk/openai" } },
        ["claude-x"] = { provider = { npm = "@ai-sdk/anthropic" } },
        ["gemini-x"] = { provider = { npm = "@ai-sdk/google" } },
        ["glm-x"] = {},
    })
    local mock = inventory({ "gpt-x", "claude-x", "gemini-x", "glm-x", "unlisted" })
    local provider = register(mock)
    uji.provider.load("opencode-test")
    local routes = {
        ["gpt-x"] = "/v1/responses",
        ["claude-x"] = "/v1/messages",
        ["gemini-x"] = "/v1/models/gemini-x:streamGenerateContent?alt=sse",
        ["glm-x"] = "/v1/chat/completions",
        ["unlisted"] = "/v1/chat/completions",
    }
    for id, path in pairs(routes) do
        local before = #mock.requests
        provider.api:stream({
            model = id,
            provider = { id = provider.id, base_url = provider.base_url },
            auth = { key = "test-key" },
            messages = { { type = "user", text = "hi" } },
            tools = {},
            reasoning = false,
            max_output = 16,
            cache = "off",
        }, { fail = function() end })
        assert.equal(before + 1, #mock.requests, id)
        assert.equal(path, mock.requests[#mock.requests].path, id)
    end
end)

it("lists models.dev's models when the endpoint names none", function()
    metadata({ ["glm-x"] = { limit = { context = 200000, output = 32000 } }, ["gpt-x"] = {} })
    local mock = server.start(function()
        return server.status(500, "boom")
    end)
    register(mock)
    local rows = uji.provider.load("opencode-test").models
    assert.same(
        { "glm-x", "gpt-x" },
        list.mapped(rows, function(row)
            return row.id
        end)
    )
    assert.equal(200000, find(rows, "glm-x").context)
end)

it("lists the endpoint's models when models.dev cannot be read", function()
    local request = uji.http.request
    uji.http.request = function(opts, ...)
        if opts.url == METADATA then
            return nil, "offline"
        end
        return request(opts, ...)
    end
    local mock = inventory({ "glm-x" })
    register(mock)
    local rows = uji.provider.load("opencode-test").models
    assert.same(
        { "glm-x" },
        list.mapped(rows, function(row)
            return row.id
        end)
    )
    assert.is_nil(find(rows, "glm-x").context)
end)

it("sends a model with no npm by the protocol its api names", function()
    metadata({ ["claude-x"] = { provider = { api = "https://opencode.ai/inference/anthropic/v1" } } })
    local mock = inventory({ "claude-x" })
    local provider = register(mock)
    uji.provider.load("opencode-test")
    provider.api:stream({
        model = "claude-x",
        provider = { id = provider.id, base_url = provider.base_url },
        auth = { key = "test-key" },
        messages = { { type = "user", text = "hi" } },
        tools = {},
        reasoning = false,
        max_output = 16,
        cache = "off",
    }, { fail = function() end })
    assert.equal("/v1/messages", mock.requests[#mock.requests].path)
end)

it("sends the session and its own user agent on chat, title and compaction requests", { timeout = 20 }, function()
    metadata({ ["glm-x"] = { limit = { context = 4000, output = 1000 } } })
    local round = 0
    local mock = inventory({ "glm-x" }, function(request)
        if not server.has_tools(request) then
            local compacting = server.summarising(request)
            return server.text(compacting and "SUMMARY" or "Title")
        end
        round = round + 1
        if round == 1 then
            return server.tool_calls(0, { { "run_command", [[{"command":"yes 'a long line of command output' | head -n 2000"}]] } })
        end
        return server.text("done")
    end)
    register(mock)
    agent.allow_all()
    uji.model.use({ provider = "opencode-test", model = "glm-x" })
    uji.provider.load("opencode-test")
    local turned, titled = sys.promise(), sys.promise()
    uji.on("turn_finished", function()
        turned:resolve()
    end)
    uji.on("session_titled", function()
        titled:resolve()
    end)
    uji.session.submit("go")
    turned:await()
    titled:await()
    local kinds = {}
    for _, request in ipairs(mock.requests) do
        if request.path == "/v1/chat/completions" then
            assert.equal(app.session.id, request.headers["x-opencode-session"])
            assert.equal("uji", request.headers["x-opencode-client"])
            assert.equal("uji/", request.headers["user-agent"]:sub(1, 4))
            local kind = server.has_tools(request) and "turn" or server.summarising(request) and "compaction" or "title"
            kinds[kind] = true
        end
    end
    assert.same({ turn = true, title = true, compaction = true }, kinds)
end)

it("sends earlier thinking back as reasoning_content on the chat API", function()
    metadata({ ["glm-x"] = {} })
    local mock = inventory({ "glm-x" })
    local provider = register(mock)
    uji.provider.load("opencode-test")
    provider.api:stream({
        model = "glm-x",
        provider = { id = provider.id, base_url = provider.base_url },
        auth = { key = "test-key" },
        messages = {
            { type = "user", text = "hi" },
            { type = "assistant", text = "hello", reasoning = "they said hi" },
            { type = "assistant", text = "again" },
            { type = "user", text = "next" },
        },
        tools = {},
        reasoning = true,
        max_output = 16,
        cache = "off",
    }, { fail = function() end })
    local sent = mock.requests[#mock.requests].body.messages
    assert.equal("they said hi", sent[2].reasoning_content)
    assert.is_nil(sent[3].reasoning_content)
end)
