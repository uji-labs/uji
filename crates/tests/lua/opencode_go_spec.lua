local function configured_go()
    -- Routing fixtures use the existing provider model-override contract.
    local rows = {}
    for id in
        ([[glm-5.2 glm-5.3 glm-5.3-flash kimi-k2.6 kimi-k2.7-code kimi-k3
        longcat-2.0 longcat-2.5-preview-free deepseek-v4-pro deepseek-v4-flash
        deepseek-v4.1-flash deepseek-v4-flash-vision-exp mimo-v2.5 mimo-v2.5-pro
        mimo-v2.6-flash mimo-v2.6-pro hy4-preview hy3 space-bunny-free
        minimax-m3 minimax-m2.7 qwen3.8-max qwen3.8-flash qwen3.7-plus
        grok-4.7 grok-4.6 gpt-6-luna gpt-5.6-luna muse-spark-1.3-contributor muse-spark-1.2-contributor]]):gmatch("%S+")
    do
        rows[#rows + 1] = { id = id, context = 1000000, output = 4096, reasoning = true }
    end
    uji.provider.add({ id = "opencode-go", models = rows })
end

it("keeps the owning session header on auxiliary requests", function()
    configured_go()
    local model = require("uji.core.model")
    local sys = require("uji.sys")
    local title = require("uji.core.agent.title")
    local compactor = require("uji.core.agent.compactor")
    require("uji.core.auth").save_key("opencode-go", "synthetic-test-key")
    model.set_setting("llm.provider", "opencode-go")
    local sent = {}
    sys.net.open = function(opts)
        assert(opts.headers["x-opencode-session"] == "owning-session")
        assert(opts.headers["User-Agent"] == "uji")
        sent[#sent + 1] = opts.url
        return nil, "recorded; no network"
    end
    for _, id in ipairs({ "deepseek-v4.1-flash", "minimax-m3", "muse-spark-1.3-contributor" }) do
        model.set_setting("llm.model", id)
        model.resolve()
        local answer, failure = title.generate("Fix the build", "owning-session")
        assert(answer == nil and failure ~= nil)
        compactor.generate({ { type = "user", text = "Fix the build" } }, nil, "owning-session")
        compactor.fold(
            { { type = "user", text = string.rep("earlier ", 100) }, { type = "user", text = "recent" } },
            { window = 1, reserve = 0 },
            1,
            "owning-session"
        )
    end
    assert(#sent == 9)
    assert(sent[1]:match("/chat/completions$"))
    assert(sent[4]:match("/messages$"))
    assert(sent[7]:match("/responses$"))
end)

it("reports a notice for failed title requests with session routing", function()
    configured_go()
    local app = require("uji.core.app")
    local model = require("uji.core.model")
    local sys = require("uji.sys")
    local event = require("uji.core.event")
    require("uji.core.auth").save_key("opencode-go", "synthetic-test-key")
    model.set_setting("llm.provider", "opencode-go")
    model.set_setting("llm.model", "deepseek-v4.1-flash")
    model.resolve()
    local noticed = sys.promise()
    event.on("notice", function(info)
        if info.text:find("could not name the session", 1, true) then
            noticed:resolve(info.text)
        end
    end)
    local requests = 0
    sys.net.open = function(opts)
        requests = requests + 1
        assert(opts.headers["x-opencode-session"] == app.session.id)
        return nil, "controlled transport failure"
    end
    app.agent.compact_if_needed = function()
        return false
    end
    app.agent.prompt = function()
        return "", {}
    end
    app.agent.start = function() end
    app.agent:submit("Fix the build")
    local notice = noticed:await()
    assert(notice:find("controlled transport failure", 1, true))
    assert(requests == 1 and app.session:untitled())
end)

it("routes each configured Go model independently of Zen and OpenAI", function()
    configured_go()
    local catalog = require("uji.core.catalog")
    local sys = require("uji.sys")
    local go = assert(catalog.get("opencode-go"))
    local paths = {}
    for _, id in ipairs({ "minimax-m3", "minimax-m2.7", "qwen3.8-max", "qwen3.8-flash", "qwen3.7-plus" }) do
        paths[id] = "/messages"
    end
    for _, id in ipairs({
        "grok-4.7",
        "grok-4.6",
        "gpt-6-luna",
        "gpt-5.6-luna",
        "muse-spark-1.3-contributor",
        "muse-spark-1.2-contributor",
    }) do
        paths[id] = "/responses"
    end
    local requests = {}
    sys.net.open = function(opts)
        requests[#requests + 1] = { url = opts.url, method = opts.method, headers = opts.headers, body = uji.json.decode(opts.body) }
        return nil, "recorded; no network"
    end
    local reply = {
        text = function() end,
        reasoning = function() end,
        done = function()
            error("unexpected provider response")
        end,
        fail = function() end,
    }
    for _, model in ipairs(go.models) do
        go.api:stream({
            model = model.id,
            provider = { id = go.id, base_url = go.base_url },
            auth = { key = "fixture-key" },
            session = "parent",
            system = "Follow instructions.",
            messages = {
                { type = "user", text = "Read notes." },
                {
                    type = "assistant",
                    text = "",
                    tool_calls = { { id = "call_1", name = "read_file", arguments = '{"path":"notes.txt"}' } },
                },
                { type = "tool", name = "read_file", tool_call_id = "call_1", content = "alpha" },
            },
            tools = {
                {
                    name = "read_file",
                    description = "Read a file.",
                    parameters = { type = "object", properties = { path = { type = "string" } } },
                },
            },
            reasoning = false,
            effort = "off",
            max_output = 4096,
            cache = "off",
        }, reply)
        local sent = requests[#requests]
        assert(sent.url == go.base_url .. (paths[model.id] or "/chat/completions"))
        assert(sent.body.model == model.id and sent.method == "POST")
        assert(sent.headers["User-Agent"] == "uji" and sent.headers["x-opencode-session"] == "parent")
        if paths[model.id] == "/messages" then
            assert(sent.headers["x-api-key"] == "fixture-key" and sent.headers["anthropic-version"] == "2023-06-01")
        else
            assert(sent.headers.Authorization == "Bearer fixture-key")
        end
    end
    local before = #requests
    local failed
    go.api:stream({ model = "unsupported" }, {
        fail = function(err)
            failed = err
        end,
    })
    assert(#requests == before and failed.kind == "provider")
    local zen = assert(catalog.get("opencode-zen"))
    assert(zen.base_url == "https://opencode.ai/zen/v1")
    local openai = assert(catalog.get("openai"))
    assert(openai.api:url({ provider = { base_url = openai.base_url } }) == "https://api.openai.com/v1/responses")

    assert(#requests == 30)
    local function sent(model)
        for _, request in ipairs(requests) do
            if request.body.model == model then
                return request
            end
        end
        error("missing model request: " .. model)
    end
    local chat = sent("glm-5.2")
    assert(chat.body.messages[1].content == "Follow instructions.")
    assert(chat.body.messages[3].tool_calls[1].id == "call_1")
    assert(chat.body.messages[4].tool_call_id == "call_1")
    local messages = sent("minimax-m3")
    assert(messages.body.messages[2].content[1].id == "call_1")
    assert(messages.body.messages[3].content[1].tool_use_id == "call_1")
    local responses = sent("muse-spark-1.3-contributor")
    assert(responses.body.input[1].role == "system")
    assert(responses.body.input[1].content == "Follow instructions.")
    assert(responses.body.input[3].call_id == "call_1")
    assert(responses.body.input[4].call_id == "call_1")
    assert(responses.body.store == false)
end)

it("sets Go headers from the request session", function()
    configured_go()
    local go = assert(require("uji.core.catalog").get("opencode-go"))
    local sys, headers = require("uji.sys"), {}
    sys.net.open = function(opts)
        headers[#headers + 1] = opts.headers
        return nil, "recorded; no network"
    end
    local reply = { text = function() end, reasoning = function() end, done = function() end, fail = function() end }
    for _, model in ipairs({ "glm-5.2", "minimax-m3", "muse-spark-1.3-contributor" }) do
        for _, session in ipairs({ "parent", "child", "" }) do
            go.api:stream({
                model = model,
                provider = { id = go.id, base_url = go.base_url },
                auth = { key = "fixture-key" },
                session = session,
                messages = { { type = "user", text = "Hello" } },
                tools = {},
                reasoning = false,
                effort = "off",
                max_output = 4096,
                cache = "off",
            }, reply)
        end
    end
    assert(#headers == 9)
    for at = 1, #headers, 3 do
        assert(headers[at]["x-opencode-session"] == "parent")
        assert(headers[at + 1]["x-opencode-session"] == "child")
        assert(headers[at + 2]["x-opencode-session"] == nil)
        assert(headers[at + 2]["User-Agent"] == "uji")
    end
end)
