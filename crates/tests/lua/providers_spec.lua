local providers = require("uji.builtin.providers")
local server = require("support.server")
local sys = require("uji.sys")
local list = require("uji.utils.list")

local STATE = uji.provider.STATE
local PREFIX = "uji.builtin.providers."

local function counted(models, fails)
    local calls = { count = 0 }
    calls.load = function()
        calls.count = calls.count + 1
        sys.sleep(0.01)
        if fails and calls.count <= fails then
            error("offline", 0)
        end
        return models
    end
    return calls
end

local function add(id, models)
    uji.provider.add({
        id = id,
        name = id,
        api = uji.api.openai(),
        base_url = "http://127.0.0.1:9",
        models = models,
    })
end

local function ids(rows)
    local out = {}
    for index, row in ipairs(rows) do
        out[index] = row.id
    end
    return out
end

local function state(id)
    return uji.provider.get(id).state
end

it("loads a provider's models only once they are needed", function()
    local calls = counted({ { id = "fetched", context = 1000 } })
    add("lazy", calls.load)
    assert.equal(0, calls.count)
    assert.equal(STATE.IDLE, state("lazy"))
    assert.same({ "fetched" }, ids(uji.provider.load("lazy").models))
    assert.same({ "fetched" }, ids(uji.provider.load("lazy").models))
    assert.equal(1, calls.count)
    assert.equal(STATE.LOADED, state("lazy"))
end)

it("shares one load between everyone waiting for it", function()
    local calls = counted({ { id = "fetched" } })
    add("shared", calls.load)
    local done = sys.promise()
    uji.provider.load("shared", function()
        done:resolve()
    end)
    sys.sleep(0)
    assert.equal(STATE.LOADING, state("shared"))
    uji.provider.load("shared")
    done:await()
    assert.equal(1, calls.count)
end)

it("keeps the listed models when loading fails and loads again later", function()
    local calls = counted({ { id = "fetched" } }, 1)
    add("flaky", { "listed" })
    add("flaky", calls.load)
    local row = uji.provider.load("flaky")
    assert.same({ "listed" }, ids(row.models))
    assert.equal(STATE.FAILED, row.state)
    assert.equal("offline", row.error)
    row = uji.provider.load("flaky")
    assert.same({ "listed", "fetched" }, ids(row.models))
    assert.equal(STATE.LOADED, row.state)
    assert.is_nil(row.error)
    assert.equal(2, calls.count)
end)

it("resolves the current model again once its provider has loaded", function()
    local calls = counted({ { id = "thinker", reasoning = true, efforts = { "low", "high" } } })
    add("background", calls.load)
    local changed = sys.promise()
    uji.on("model_changed", function()
        if #uji.model.efforts() > 0 then
            changed:resolve()
        end
    end)
    uji.model.use({ provider = "background", model = "thinker" })
    assert.same({}, uji.model.efforts())
    assert.is_true(uji.task.timeout(5, function()
        changed:await()
    end))
    assert.same({ "low", "high" }, uji.model.efforts())
end)

it("offers gemini 4 argon the thinking levels it was released with", function()
    uji.model.use({ provider = "google", model = "gemini-4-argon" })
    assert.same({ "low", "medium", "high" }, uji.model.efforts())
end)

it("rejects models that are neither a list nor a function", function()
    local ok, err = pcall(add, "broken", "not a list")
    assert.is_false(ok)
    assert.truthy(err:find("models must be a list or a function that returns one", 1, true))
end)

it("gives nothing for an unknown provider and points a load of one at the caller", function()
    assert.is_nil(uji.provider.get("nobody"))
    local ok, err = pcall(function()
        local row = uji.provider.load("nobody")
        return row
    end)
    assert.is_false(ok)
    assert.truthy(err:find("providers_spec.lua", 1, true))
    assert.truthy(err:find("no provider is registered as nobody", 1, true))
end)

it("names every provider after the file that registers it", function()
    providers.all()
    local registered = {}
    for _, provider in ipairs(uji.provider.list()) do
        registered[provider.id] = true
    end
    local names = list.mapped(uji.modules("uji.builtin.providers"), function(module)
        return module:sub(#PREFIX + 1)
    end)
    for _, id in ipairs(names) do
        assert.is_true(registered[id] == true, id .. " has no provider named after its file")
    end
end)

it("keeps a saved DeepSeek Flash id on Flash when its alias retires", function()
    providers.load("deepseek")
    require("uji.core.model").remember("deepseek", "deepseek-v4-flash")
    uji.model.use({ provider = "deepseek" })
    assert.equal("deepseek-flash", uji.model.current().model)
end)

it("lists the models a llama.cpp server holds", function()
    providers.all()
    local mock = server.start(function()
        return {
            status = 200,
            body = uji.json.encode({ data = { { id = "qwen3-8b" }, { id = "llama-3.3-70b" } } }),
        }
    end)
    uji.provider.add({ id = "llamacpp", base_url = mock.url .. "/v1" })
    local loaded = uji.provider.load("llamacpp")
    assert.equal(STATE.LOADED, loaded.state)
    assert.same({ "qwen3-8b", "llama-3.3-70b" }, ids(loaded.models))
    uji.model.use({ provider = "llamacpp" })
    assert.equal("qwen3-8b", uji.model.current().model)
end)

it("lists the chat models in the Cheaper Inference catalog", function()
    providers.all()
    local mock = server.start(function()
        return {
            status = 200,
            body = uji.json.encode({
                models = {
                    {
                        id = "gpt-5.4-mini",
                        model_type = "text",
                        supported_endpoints = { "/v1/chat/completions", "/v1/responses" },
                        context_length = 400000,
                        max_output_tokens = 128000,
                        supports_reasoning = true,
                        supports_vision = true,
                    },
                    { id = "gpt-5.4-pro", model_type = "text", supported_endpoints = { "/v1/responses" } },
                    { id = "text-embedding-3-small", model_type = "embedding", endpoint = "/v1/embeddings" },
                },
            }),
        }
    end)
    uji.provider.add({ id = "cheaperinference", base_url = mock.url .. "/v1" })
    local loaded = uji.provider.load("cheaperinference")
    assert.equal(STATE.LOADED, loaded.state)
    assert.same({ "gpt-5.4-mini" }, ids(loaded.models))
    assert.equal(400000, loaded.models[1].context)
    assert.equal(128000, loaded.models[1].output)
    assert.is_true(loaded.models[1].reasoning)
    assert.is_true(loaded.models[1].images)
end)

it("leaves a provider file alone until something asks for it", function()
    assert.is_nil(package.loaded[PREFIX .. "openrouter"], "the boot loaded it anyway")
    assert.is_not_nil(uji.provider.get("openrouter"))
    assert.is_not_nil(package.loaded[PREFIX .. "openrouter"], "asking for it loads it")
end)
