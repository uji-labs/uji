local auth = require("uji.auth")
local catalog = require("uji.catalog")
local context = require("uji.context")
local event = require("uji.event")
local sys = require("uji.sys")
local wire = require("uji.wire")

local DEFAULT_MAX_OUTPUT = 8192
local EFFORTS = { off = true, minimal = true, low = true, medium = true, high = true }
local NOT_CONFIGURED = "no provider is configured - run /login to set one up"

local M = {
    EFFORTS = { "off", "minimal", "low", "medium", "high" },
    DEFAULT_MAX_OUTPUT = DEFAULT_MAX_OUTPUT,
    current = { id = "", model = "", effort = "off", caches = false },
}

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

function M.resolve()
    local id = M.setting("llm.provider") or ""
    local provider = catalog.get(id)
    local stored = M.setting("llm.model")
    local model = provider and provider:usable_model(stored) or stored or ""
    local base_url = M.setting("llm.base_url")
    if base_url == "" then
        base_url = nil
    end
    if not base_url and provider and provider.base_url ~= "" then
        base_url = provider.base_url
    end
    local effort = M.setting("llm.effort")
    if not (effort and EFFORTS[effort] and provider and provider:reasons(model)) then
        effort = "off"
    end
    M.current = {
        id = id,
        provider = provider,
        name = provider and provider.name or (id ~= "" and id or nil),
        model = model,
        base_url = base_url,
        effort = effort,
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

function M.budget()
    local current = M.current
    local budget = current.provider and current.provider:budget(current.model)
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
    local current = M.current
    local budget = current.provider and current.provider:budget(current.model)
    return budget and budget.window
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
        return nil, { kind = "provider", message = tostring(first) }
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
    local spec = wire.get(provider.wire)
    if not spec then
        return nil, { kind = "provider", message = "no wire is registered as " .. tostring(provider.wire) }
    end
    local credentials, failure = auth.resolve(provider)
    if not credentials then
        return nil, failure
    end
    request.model = request.model or current.model
    request.provider = { id = provider.id, base_url = current.base_url or "", compat = provider.compat }
    request.auth = credentials
    return M.call(spec.stream, request, reply)
end

function M.generate(opts)
    return M.stream({
        model = M.current.model,
        system = opts.system,
        messages = opts.messages,
        tools = {},
        effort = "off",
        max_output = DEFAULT_MAX_OUTPUT,
        cache = "off",
    })
end

return M
