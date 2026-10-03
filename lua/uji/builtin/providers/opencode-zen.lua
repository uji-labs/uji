local BASE_URL = "https://opencode.ai/zen/v1"
local listed = require("uji.builtin.opencode")
local formats = {}

local function group(api, ids)
    local headers = api.headers
    function api:headers(request, ...)
        local out = headers(self, request, ...)
        out["User-Agent"] = "uji"
        if request.session and request.session ~= "" then
            out["x-opencode-session"] = request.session
        end
        return out
    end
    for id in ids:gmatch("%S+") do
        formats[id] = api
    end
end

-- Zen assignments differ from Go: opencode.ai/docs/zen/#endpoints.
group(
    uji.api.openai(),
    [[qwen3.8-max deepseek-v4.1-flash deepseek-v4-pro deepseek-v4-flash deepseek-v4-flash-vision-exp
    minimax-m3 minimax-m2.7 minimax-m2.5 glm-5.3-flash glm-5.3 glm-5.2 glm-5.1 glm-5
    kimi-k2.5 kimi-k2.6 kimi-k2.7-code kimi-k3 big-pickle space-bunny-free longcat-2.5-preview-free
    fledge-alpha-free mimo-v2.6-flash-free mimo-v2.5-free ling-3.1-flash-free ling-3.0-flash-fin-free
    nemotron-3-ultra-free nemotron-3.5-lightning-free]]
)
group(
    uji.api.anthropic(),
    [[claude-fable-5-1 claude-fable-5 claude-opus-5-5 claude-opus-5 claude-opus-4-8
    claude-opus-4-7 claude-opus-4-6 claude-opus-4-5 claude-sonnet-5 claude-sonnet-4-6
    claude-sonnet-4-5 claude-haiku-4-5 qwen3.8-flash qwen3.7-max qwen3.7-plus qwen3.6-plus qwen3.5-plus]]
)
group(
    uji.api.responses(),
    [[gpt-6-astra gpt-6-sol gpt-6.1-sol gpt-6-luna gpt-5.6-sol gpt-5.6-terra gpt-5.6-luna
    gpt-5.5 gpt-5.5-pro gpt-5.4 gpt-5.4-pro gpt-5.4-mini gpt-5.4-nano gpt-5.3-codex gpt-5.3-codex-spark
    gpt-5.2 gpt-5.2-codex gpt-5.1 gpt-5.1-codex gpt-5.1-codex-max gpt-5.1-codex-mini
    gpt-5 gpt-5-codex gpt-5-nano grok-4.7 grok-4.6 grok-4.5 grok-build-0.1
    muse-spark-1.3 muse-spark-1.2 muse-spark-1.3-contributor-free]]
)
group(
    uji.api.gemini(),
    [[gemini-3.8-flash gemini-3.7-flash gemini-3.6-flash gemini-3.5-flash
    gemini-3.5-flash-lite gemini-3.1-pro gemini-3-flash]]
)

local Zen = uji.class()
local loaded = require("uji.sys").promise()
local registered, original_api

local function owns_provider()
    return require("uji.core.catalog").get("opencode-zen") == registered and registered.api == original_api
end

function Zen:ready(model)
    if not owns_provider() then
        return nil, { kind = "provider", message = "OpenCode Zen provider changed while loading" }
    end
    if registered:model(model) then
        return true
    end
    local problem = loaded:await()
    if not owns_provider() then
        return nil, { kind = "provider", message = "OpenCode Zen provider changed while loading" }
    end
    if problem then
        return nil, { kind = "provider", message = problem .. "; run /reload to retry loading OpenCode Zen models" }
    end
    return true
end

function Zen:efforts(model)
    local api = formats[model]
    return api and api.efforts and api:efforts(model) or { "off", "minimal", "low", "medium", "high" }
end

function Zen:stream(request, reply)
    local available, failure = self:ready(request.model)
    if not available then
        return reply.fail(failure)
    end
    local provider = registered
    if not request.model or request.model == "" then
        request.model = provider:default_model()
    end
    local api = formats[request.model]
    if not api or not provider:model(request.model) then
        return reply.fail({ kind = "provider", message = "unsupported or unavailable OpenCode Zen model: " .. tostring(request.model) })
    end
    return api:stream(request, reply)
end

uji.provider.add({
    id = "opencode-zen",
    name = "OpenCode Zen",
    api = Zen(),
    base_url = BASE_URL,
    auth_env = { "OPENCODE_API_KEY" },
    models = {},
})
registered = require("uji.core.catalog").get("opencode-zen")
original_api = registered.api

-- HTTP waits must run outside require(), which cannot yield.
uji.schedule(function()
    local ok, failure = pcall(function()
        assert(owns_provider(), "OpenCode Zen provider changed while loading")
        local models, problem = listed(BASE_URL, "opencode", formats)
        assert(owns_provider(), "OpenCode Zen provider changed while loading")
        if problem then
            error(problem, 0)
        end
        for index = #models, 1, -1 do
            if registered:model(models[index].id) then
                table.remove(models, index)
            end
        end
        uji.provider.add({ id = "opencode-zen", models = models })
        local model = require("uji.core.model")
        local current = model.current
        if current.provider == registered then
            model.resolve({
                provider = current.id,
                model = current.model ~= "" and current.model or registered:default_model(),
                effort = current.wanted_effort,
            })
        end
    end)
    loaded:resolve(not ok and tostring(failure) or nil)
end)
