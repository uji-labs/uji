local auth = require("uji.core.auth")
local catalog = require("uji.core.catalog")
local context = require("uji.core.context")
local event = require("uji.core.event")
local images = require("uji.core.images")
local sys = require("uji.sys")

local DEFAULT_MAX_OUTPUT = 8192
local NOT_CONFIGURED = "no provider is configured - run /login to set one up"

local RANK = {}
for index, name in ipairs(catalog.EFFORTS) do
    RANK[name] = index
end

local M = {
    EFFORTS = catalog.EFFORTS,
    DEFAULT_MAX_OUTPUT = DEFAULT_MAX_OUTPUT,
    current = { id = "", model = "", efforts = {}, reasoning = false, caches = false },
}

function M.nearest(efforts, wanted)
    local rank = RANK[wanted]
    if not rank then
        return nil
    end
    local below, above
    for _, name in ipairs(efforts) do
        local at = RANK[name]
        if at == rank then
            return name
        elseif at > rank and (not above or at < RANK[above]) then
            above = name
        elseif at < rank and (not below or at > RANK[below]) then
            below = name
        end
    end
    return above or below
end

function M.attach(store)
    M.store = store
end

function M.setting(key)
    return M.store and M.store:setting(key)
end

function M.set_setting(key, value)
    if M.store then
        M.store:set_setting(key, value)
    end
end

function M.resolve(choice)
    choice = choice or {}
    local saved = M.setting("llm.provider") or ""
    local id = choice.provider or saved
    local provider = catalog.get(id)
    local stored = M.setting("llm.model")
    local model = choice.model or provider and provider:usable_model(stored) or stored or ""
    local base_url = id == saved and M.setting("llm.base_url") or nil
    if base_url == "" then
        base_url = nil
    end
    if not base_url and provider and provider.base_url ~= "" then
        base_url = provider.base_url
    end
    local efforts = provider and provider:efforts(model) or {}
    local effort = M.nearest(efforts, choice.effort or M.setting("llm.effort") or "off")
    M.current = {
        id = id,
        provider = provider,
        name = provider and provider.name or (id ~= "" and id or nil),
        model = model,
        base_url = base_url,
        effort = effort,
        efforts = efforts,
        reasoning = #efforts > 0,
        caches = provider ~= nil and provider:caches(model),
    }
    event.emit("model_changed", { provider = id, model = model })
    event.emit("status_changed", {})
    return M.current
end

function M.remember(provider_id, model)
    M.set_setting("llm.model", model)
    M.set_setting("llm.model." .. provider_id, model)
end

function M.model_for(provider)
    local stored = M.setting("llm.model." .. provider.id) or M.setting("llm.model")
    return provider:usable_model(stored)
end

function M.max_output()
    local current = M.current
    local entry = current.provider and current.provider:model(current.model)
    return entry and entry.output or DEFAULT_MAX_OUTPUT
end

local function measured()
    local current = M.current
    return current.provider and current.provider:budget(current.model)
end

function M.budget()
    local budget = measured()
    if not budget then
        return nil
    end
    if context.compaction.reserve then
        budget.reserve = math.min(context.compaction.reserve, budget.window)
    end
    return budget
end

function M.usable(budget)
    return math.max(budget.window - budget.reserve, 0)
end

function M.window()
    local budget = measured()
    return budget and budget.window
end

local function text_only(current)
    return "llm.images." .. current.id .. "/" .. current.model
end

function M.images()
    local current = M.current
    local declared = current.provider and current.provider:images(current.model)
    if declared ~= nil then
        return declared
    end
    if M.setting(text_only(current)) == "no" then
        return false
    end
    return nil
end

function M.retention()
    return M.current.caches and context.cache or "off"
end

function M.call(stream, request, reply)
    local promise = sys.promise()
    local handler = {
        text = reply and reply.text or function() end,
        reasoning = reply and reply.reasoning or function() end,
        done = function(answer)
            promise:resolve(answer)
        end,
        fail = function(failure)
            promise:resolve(nil, failure)
        end,
    }
    local ok, first, second = pcall(stream, request, handler)
    if not ok then
        return nil, { kind = "provider", message = sys.message(first) }
    end
    if type(first) == "table" then
        return first
    end
    if first == nil and type(second) == "table" then
        return nil, second
    end
    return promise:await()
end

function M.stream(request, reply)
    local current = M.current
    local provider = current.provider
    if current.id == "" or not provider then
        return nil, { kind = "provider", message = NOT_CONFIGURED }
    end
    local api = provider.api
    local credentials, missing = auth.resolve(provider)
    if not credentials then
        return nil, missing
    end
    request.model = request.model or current.model
    request.provider = { id = provider.id, base_url = current.base_url or "" }
    if request.reasoning == nil then
        request.reasoning = current.reasoning
    end
    request.auth = credentials
    local accepts = M.images()
    local messages = request.messages
    request.messages = images.prepare(messages, accepts)
    local function stream(...)
        return api:stream(...)
    end
    local answer, failure = M.call(stream, request, reply)
    if answer or accepts ~= nil or not images.present(request.messages) or not images.refused(failure) then
        return answer, failure
    end
    request.messages = images.prepare(messages, false)
    answer, failure = M.call(stream, request, reply)
    if answer then
        M.set_setting(text_only(current), "no")
    end
    return answer, failure
end

function M.generate(opts)
    return M.stream({
        model = M.current.model,
        system = opts.system,
        messages = opts.messages,
        tools = {},
        effort = M.nearest(M.current.efforts, "off"),
        max_output = DEFAULT_MAX_OUTPUT,
        cache = "off",
    })
end

return M
