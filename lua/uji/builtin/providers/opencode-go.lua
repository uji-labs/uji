local BASE_URL = "https://opencode.ai/zen/go/v1"
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

-- Endpoint formats are service-specific: opencode.ai/docs/go/#endpoints.
group(
    uji.api.openai(),
    [[glm-5.2 glm-5.3 glm-5.3-flash kimi-k2.6 kimi-k2.7-code kimi-k3
    longcat-2.0 longcat-2.5-preview-free deepseek-v4-pro deepseek-v4-flash
    deepseek-v4.1-flash deepseek-v4-flash-vision-exp mimo-v2.5 mimo-v2.5-pro
    mimo-v2.6-flash mimo-v2.6-pro hy4-preview hy3 space-bunny-free]]
)
group(uji.api.anthropic(), [[minimax-m3 minimax-m2.7 qwen3.8-max qwen3.8-flash qwen3.7-plus]])
group(
    uji.api.responses(),
    [[grok-4.7 grok-4.6 gpt-6-luna gpt-5.6-luna
    muse-spark-1.3-contributor muse-spark-1.2-contributor]]
)

local Go = uji.class()
local loaded = require("uji.sys").promise()
local registered, original_api

local function owns_provider()
    return require("uji.core.catalog").get("opencode-go") == registered and registered.api == original_api
end

function Go:ready(model)
    if not owns_provider() then
        return nil, { kind = "provider", message = "OpenCode Go provider changed while loading" }
    end
    if registered:model(model) then
        return true
    end
    local problem = loaded:await()
    if not owns_provider() then
        return nil, { kind = "provider", message = "OpenCode Go provider changed while loading" }
    end
    if problem then
        return nil, { kind = "provider", message = problem .. "; run /reload to retry loading OpenCode Go models" }
    end
    return true
end

function Go:efforts(model)
    local api = formats[model]
    return api and api.efforts and api:efforts(model) or { "off", "minimal", "low", "medium", "high" }
end

function Go:stream(request, reply)
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
        return reply.fail({ kind = "provider", message = "unsupported or unavailable OpenCode Go model: " .. tostring(request.model) })
    end
    return api:stream(request, reply)
end

uji.provider.add({
    id = "opencode-go",
    name = "OpenCode Go",
    api = Go(),
    base_url = BASE_URL,
    auth_env = { "OPENCODE_API_KEY" },
    models = {},
})
registered = require("uji.core.catalog").get("opencode-go")
original_api = registered.api

-- HTTP waits must run outside require(), which cannot yield.
uji.schedule(function()
    local ok, failure = pcall(function()
        assert(owns_provider(), "OpenCode Go provider changed while loading")
        local models, problem = listed(BASE_URL, "opencode-go", formats)
        assert(owns_provider(), "OpenCode Go provider changed while loading")
        if problem then
            error(problem, 0)
        end
        for index = #models, 1, -1 do
            if registered:model(models[index].id) then
                table.remove(models, index)
            end
        end
        uji.provider.add({ id = "opencode-go", models = models })
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
