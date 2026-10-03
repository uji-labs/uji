local function suspended_provider(id, source, name)
    local sys, catalog = require("uji.sys"), require("uji.core.catalog")
    local entered, release = sys.promise(), sys.promise()
    local metadata = {
        [source] = {
            models = {
                [name] = {
                    limit = { context = 20000, output = 2048 },
                    reasoning = true,
                    cost = { cache_read = 0 },
                    reasoning_options = { { type = "effort", values = { "low", "high" } } },
                },
            },
        },
    }
    uji.http.request = function(opts)
        entered:resolve()
        release:await()
        return {
            status = 200,
            body = uji.json.encode(opts.url == "https://models.dev/api.json" and metadata or { data = { { id = name } } }),
        }
    end
    catalog.remove(id)
    package.loaded["uji.builtin.providers." .. id] = nil
    require("uji.builtin.providers." .. id)
    return catalog.get(id), entered, release
end

it("loads capabilities before capturing the first turn and auxiliary request", function()
    local sys, app, model = require("uji.sys"), require("uji.core.app"), require("uji.core.model")
    local provider, entered, release = suspended_provider("opencode-go", "opencode-go", "deepseek-v4.1-flash")
    require("uji.core.auth").save_key(provider.id, "synthetic-test-key")
    model.resolve({ provider = provider.id, model = "deepseek-v4.1-flash", effort = "high" })
    app.session:rename("fixture")
    local calls, finished = {}, sys.promise()
    require("uji.core.event").on("turn_finished", function()
        finished:resolve()
    end)
    sys.net.open = function(opts)
        calls[#calls + 1] = uji.json.decode(opts.body)
        if app.agent.turn then
            assert.equal("short", app.agent.turn.loop.cache)
        end
        return {
            status = 400,
            headers = {},
            read = function()
                return "fixture failure"
            end,
        }
    end
    uji.session.submit("first turn")
    entered:await()
    assert.is_true(app.agent:working())
    assert.equal(0, #calls)
    release:resolve()
    finished:await()
    assert.equal(1, #calls)
    assert.equal("deepseek-v4.1-flash", calls[1].model)
    assert.equal("high", calls[1].reasoning_effort)
    assert.equal(2048, calls[1].max_tokens)
    assert.equal("high", uji.model.current().effort)
    model.generate({ session = app.session.id, messages = {}, system = "auxiliary" })
    assert.equal(2, #calls)
    assert.equal("low", calls[2].reasoning_effort)
    assert.equal(2048, calls[2].max_tokens)
end)

it("does not inherit another provider's model when switching before loading", function()
    local sys, model = require("uji.sys"), require("uji.core.model")
    local provider, entered, release = suspended_provider("opencode-go", "opencode-go", "deepseek-v4.1-flash")
    require("uji.core.auth").save_key(provider.id, "synthetic-test-key")
    model.set_setting("llm.provider", "openai")
    model.set_setting("llm.model", "gpt-5.4")
    uji.model.use({ provider = provider.id, effort = "high" })
    local finished, sent = sys.promise(), nil
    sys.net.open = function(opts)
        sent = uji.json.decode(opts.body)
        return {
            status = 400,
            headers = {},
            read = function()
                return "fixture failure"
            end,
        }
    end
    sys.task.spawn(function()
        model.generate({ messages = {}, system = "auxiliary" })
        finished:resolve()
    end)
    entered:await()
    release:resolve()
    finished:await()
    assert.is_not_nil(sent)
    assert.equal("deepseek-v4.1-flash", sent.model)
    assert.equal("deepseek-v4.1-flash", uji.model.current().model)
    assert.equal("high", uji.model.current().effort)
end)

it("settles loading without publishing into removed or replaced providers", function()
    local sys, catalog = require("uji.sys"), require("uji.core.catalog")
    for _, case in ipairs({
        { id = "opencode-go", source = "opencode-go", model = "deepseek-v4.1-flash" },
        { id = "opencode-zen", source = "opencode", model = "big-pickle" },
    }) do
        for _, change in ipairs({ "remove", "replace", "api" }) do
            local original, entered, release = suspended_provider(case.id, case.source, case.model)
            local completed, problem = sys.promise(), nil
            sys.task.spawn(function()
                original.api:stream({ model = case.model }, {
                    fail = function(failure)
                        problem = failure
                    end,
                })
                completed:resolve()
            end)
            entered:await()
            local replacement_api = {
                stream = function()
                    error("replacement must not run")
                end,
            }
            if change == "api" then
                uji.provider.add({ id = case.id, api = replacement_api })
            else
                catalog.remove(case.id)
                if change == "replace" then
                    uji.provider.add({
                        id = case.id,
                        name = "Replacement",
                        base_url = "https://replacement.invalid",
                        api = replacement_api,
                        models = { "local-only" },
                    })
                end
            end
            release:resolve()
            assert.is_true(require("uji.core.task").timeout(1, function()
                completed:await()
            end))
            assert.equal("provider", problem.kind)
            assert.is_truthy(problem.message:find("changed", 1, true))
            local replacement = catalog.get(case.id)
            if replacement then
                assert.is_nil(replacement:model(case.model))
                assert.equal(replacement_api, replacement.api)
            end
        end
    end
end)

it("fetches model IDs and metadata through the existing HTTP API", function()
    local sandbox = require("support.sandbox")
    local listed = require("uji.builtin.opencode")
    local document = sandbox.read(sandbox.fixtures .. "/opencode_metadata.json")
    local calls = {}
    uji.http.request = function(opts)
        assert.equal(5, opts.timeout)
        assert.is_nil(opts.headers.Authorization)
        calls[#calls + 1] = opts.url
        if opts.url == "https://models.dev/api.json" then
            return { status = 200, body = document }
        end
        return { status = 200, body = '{"data":[{"id":"space-bunny-free"},{"id":"unsupported"},{"id":"space-bunny-free"}]}' }
    end
    local models = listed("https://opencode.ai/zen/go/v1", "opencode-go", { ["space-bunny-free"] = true })
    assert.same({ "https://opencode.ai/zen/go/v1/models", "https://models.dev/api.json" }, calls)
    assert.equal(1, #models)
    assert.equal("space-bunny-free", models[1].id)
    assert.equal(1048576, models[1].context)
    assert.equal(524288, models[1].output)
    assert.is_true(models[1].reasoning and models[1].images and models[1].cache)
    assert.same({ "low", "medium", "high", "xhigh", "max" }, models[1].efforts)
end)

it("returns no bundled models when an inventory or metadata request fails", function()
    local listed = require("uji.builtin.opencode")
    local notices = {}
    uji.notify = function(text)
        notices[#notices + 1] = text
    end
    for _, response in ipairs({
        { status = 503, body = "unavailable" },
        { status = 200, body = "invalid JSON" },
        { status = 200, body = '{"data":null}' },
    }) do
        uji.http.request = function()
            return response
        end
        assert.same({}, listed("https://opencode.ai/zen/go/v1", "opencode-go", { ["space-bunny-free"] = true }))
    end
    assert.equal(0, #notices)
end)

it("filters unsupported efforts without discarding valid remote models", function()
    local listed = require("uji.builtin.opencode")
    for _, values in ipairs({ "not a list", { "none" }, { "none", "low", "high" } }) do
        local metadata = {
            fixture = {
                models = {
                    model = {
                        limit = { context = 100, output = 10 },
                        reasoning = true,
                        reasoning_options = { { type = "effort", values = values } },
                    },
                },
            },
        }
        uji.http.request = function(opts)
            return {
                status = 200,
                body = opts.url == "https://models.dev/api.json" and uji.json.encode(metadata) or '{"data":[{"id":"model"}]}',
            }
        end
        local models = listed("https://fixture.invalid", "fixture", { model = true })
        assert.equal(1, #models)
        assert.equal("model", models[1].id)
        if type(values) == "string" or #values == 1 then
            assert.is_nil(models[1].efforts)
        else
            assert.same({ "low", "high" }, models[1].efforts)
        end
        uji.provider.add({
            id = "metadata-fixture",
            name = "Fixture",
            base_url = "https://fixture.invalid",
            api = uji.api.openai(),
            models = models,
        })
    end
end)

it("waits for provider loading and reports fetch failures instead of unavailable models", function()
    local sys = require("uji.sys")
    local catalog = require("uji.core.catalog")
    for _, case in ipairs({
        { module = "opencode-zen", source = "opencode", model = "big-pickle" },
        { module = "opencode-go", source = "opencode-go", model = "deepseek-v4.1-flash" },
    }) do
        local fetched = sys.promise()
        local metadata = { [case.source] = { models = { [case.model] = { limit = { context = 10000, output = 100 } } } } }
        uji.http.request = function(opts)
            fetched:await()
            return {
                status = 200,
                body = opts.url == "https://models.dev/api.json" and uji.json.encode(metadata)
                    or uji.json.encode({ data = { { id = case.model } } }),
            }
        end
        package.loaded["uji.builtin.providers." .. case.module] = nil
        require("uji.builtin.providers." .. case.module)
        local provider = catalog.get(case.module)
        local calls = 0
        sys.net.open = function()
            calls = calls + 1
            return nil, "recorded; no network"
        end
        local finished = sys.promise()
        local problem
        sys.task.spawn(function()
            provider.api:stream({
                model = case.model,
                provider = { id = provider.id, base_url = provider.base_url },
                auth = { key = "synthetic-key" },
                session = "waiting-session",
                messages = {},
                tools = {},
                max_output = 16,
                cache = "off",
            }, {
                fail = function(failure)
                    problem = failure
                end,
            })
            finished:resolve(true)
        end)
        sys.sleep(0)
        assert.equal(0, calls)
        fetched:resolve(true)
        finished:await()
        assert.equal(1, calls)
        assert.equal("recorded; no network", problem.message)

        uji.http.request = function()
            sys.sleep(0)
            return nil, "fixture metadata timeout"
        end
        catalog.remove(case.module)
        package.loaded["uji.builtin.providers." .. case.module] = nil
        require("uji.builtin.providers." .. case.module)
        local failed = catalog.get(case.module)
        assert.equal(0, #failed.models)
        failed.api:stream({ model = case.model }, {
            fail = function(failure)
                problem = failure
            end,
        })
        assert.is_truthy(problem.message:find("fixture metadata timeout", 1, true))
        assert.is_truthy(problem.message:find("/reload", 1, true))
        assert.equal(1, calls)
    end
end)

it("preserves local overrides and non-persisted selection while loading", function()
    local sys = require("uji.sys")
    local catalog = require("uji.core.catalog")
    local model = require("uji.core.model")
    for _, case in ipairs({
        { id = "opencode-zen", source = "opencode", model = "big-pickle", other = "minimax-m3" },
        { id = "opencode-go", source = "opencode-go", model = "deepseek-v4.1-flash", other = "glm-5.2" },
    }) do
        local fetched = sys.promise()
        local metadata = {
            [case.source] = {
                models = {
                    [case.model] = { limit = { context = 10000, output = 100 }, reasoning = true },
                    [case.other] = { limit = { context = 10000, output = 100 }, reasoning = true },
                },
            },
        }
        uji.http.request = function(opts)
            fetched:await()
            return {
                status = 200,
                body = opts.url == "https://models.dev/api.json" and uji.json.encode(metadata)
                    or uji.json.encode({ data = { { id = case.model }, { id = case.other } } }),
            }
        end
        catalog.remove(case.id)
        package.loaded["uji.builtin.providers." .. case.id] = nil
        require("uji.builtin.providers." .. case.id)
        sys.sleep(0)
        uji.provider.add({
            id = case.id,
            models = {
                { id = case.model, context = 5000, output = 42, reasoning = true, efforts = { "high" } },
            },
        })
        model.set_setting("llm.provider", "openai")
        model.resolve({ provider = case.id, model = case.model, effort = "high" })
        fetched:resolve(true)
        local deadline = sys.os.clock() + 1
        local provider = catalog.get(case.id)
        while not provider:model(case.other) and sys.os.clock() < deadline do
            sys.sleep(0)
        end
        assert.is_not_nil(provider:model(case.other))
        assert.equal(42, provider:model(case.model).output)
        assert.same({ "high" }, provider:model(case.model).efforts)
        assert.equal(case.id, uji.model.current().provider)
        assert.equal(case.model, uji.model.current().model)
        assert.equal("high", uji.model.current().effort)
        assert.equal("openai", model.setting("llm.provider"))
    end
end)

it("routes Zen requests independently of Go through the existing APIs", function()
    local sandbox = require("support.sandbox")
    local sys = require("uji.sys")
    local document = sandbox.read(sandbox.fixtures .. "/opencode_metadata.json")
    uji.http.request = function(opts)
        sys.sleep(0)
        return {
            status = 200,
            body = opts.url == "https://models.dev/api.json" and document
                or '{"data":[{"id":"big-pickle"},{"id":"claude-sonnet-4-6"},{"id":"muse-spark-1.3-contributor-free"},{"id":"gemini-3.8-flash"}]}',
        }
    end
    package.loaded["uji.builtin.providers.opencode-zen"] = nil
    require("uji.builtin.providers.opencode-zen")
    local provider = require("uji.core.catalog").get("opencode-zen")
    local deadline = sys.os.clock() + 1
    while not provider:model("big-pickle") and sys.os.clock() < deadline do
        sys.sleep(0)
    end
    assert.is_not_nil(provider:model("big-pickle"))
    local routes = {
        ["big-pickle"] = "/chat/completions",
        ["claude-sonnet-4-6"] = "/messages",
        ["muse-spark-1.3-contributor-free"] = "/responses",
        ["gemini-3.8-flash"] = "/models/gemini-3.8-flash:streamGenerateContent?alt=sse",
    }
    local seen = {}
    require("uji.sys").net.open = function(opts)
        seen[#seen + 1] = opts
        return nil, "recorded; no network"
    end
    for id, suffix in pairs(routes) do
        provider.api:stream({
            model = id,
            provider = { id = provider.id, base_url = provider.base_url },
            auth = { key = "synthetic-key" },
            session = "zen-session",
            messages = { { type = "user", text = "Hello" } },
            tools = {},
            reasoning = false,
            max_output = 16,
            cache = "off",
        }, { fail = function() end })
        local request = seen[#seen]
        assert.equal(provider.base_url .. suffix, request.url)
        assert.equal("zen-session", request.headers["x-opencode-session"])
    end
    assert.equal(4, #seen)
end)

it("keeps rejection diagnostics bounded and removes echoed API keys", function()
    require("uji.sys").net.open = function()
        return {
            status = 403,
            headers = {},
            read = function()
                return "Region denied: Bearer fixt\27ure-secret " .. string.rep("x", 3000)
            end,
        }
    end
    local _, failure = uji.api.openai():stream({
        model = "fixture",
        provider = { base_url = "https://fixture.invalid" },
        auth = { key = "fixture-secret" },
        messages = {},
        tools = {},
        max_output = 16,
        cache = "off",
    }, { fail = function() end })
    assert.equal(403, failure.status)
    assert.is_truthy(failure.message:find("Region denied", 1, true))
    assert.is_nil(failure.message:find("fixture-secret", 1, true))
    assert.is_nil(failure.message:find("\27", 1, true))
    assert.is_true(#failure.message <= 2100)
end)
