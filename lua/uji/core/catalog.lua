local plugin = require("uji.core.plugin")

local MAX_RESERVE = 20000
local EFFORTS = { "off", "minimal", "low", "medium", "high", "xhigh", "max" }
local DEFAULT_EFFORTS = { "off", "minimal", "low", "medium", "high" }

local FIELDS = {
    id = true,
    name = true,
    api = true,
    base_url = true,
    auth_env = true,
    oauth = true,
    context_window = true,
    models = true,
}

local KNOWN = {}
for _, name in ipairs(EFFORTS) do
    KNOWN[name] = true
end

local M = { providers = {}, EFFORTS = EFFORTS }

local function efforts(list, id)
    if list == nil then
        return nil
    end
    if type(list) ~= "table" then
        error("efforts of model " .. id .. " must be a list", 0)
    end
    for _, name in ipairs(list) do
        if not KNOWN[name] then
            error("model " .. id .. " lists an unknown effort `" .. tostring(name) .. "`", 0)
        end
    end
    return { unpack(list) }
end

local function model(spec)
    if type(spec) == "string" then
        return { id = spec, reasoning = false, cache = false }
    end
    if type(spec) ~= "table" or type(spec.id) ~= "string" then
        error("a model is an id or a table with an id", 0)
    end
    return {
        id = spec.id,
        context = spec.context,
        output = spec.output,
        reasoning = spec.reasoning == true,
        cache = spec.cache == true,
        images = type(spec.images) == "boolean" and spec.images or nil,
        efforts = efforts(spec.efforts, spec.id),
    }
end

local function api(value, id)
    if value ~= nil and (type(value) ~= "table" or type(value.stream) ~= "function") then
        error("the api of provider " .. id .. " needs a stream method", 0)
    end
    return value
end

local function models(list)
    local out = {}
    for index, spec in ipairs(list or {}) do
        out[index] = model(spec)
    end
    return out
end

local Provider = {}
Provider.__index = Provider

function Provider:model(id)
    for _, entry in ipairs(self.models) do
        if entry.id == id then
            return entry
        end
    end
end

function Provider:default_model()
    return self.models[1] and self.models[1].id or ""
end

function Provider:usable_model(stored)
    if stored == "" then
        stored = nil
    end
    if #self.models == 0 then
        return stored or ""
    end
    if stored and self:model(stored) then
        return stored
    end
    return self:default_model()
end

function Provider:reasons(id)
    local found = self:model(id)
    return found ~= nil and found.reasoning
end

function Provider:caches(id)
    local found = self:model(id)
    return found ~= nil and found.cache
end

function Provider:efforts(id)
    local found = self:model(id)
    if not (found and found.reasoning) then
        return {}
    end
    if found.efforts then
        return found.efforts
    end
    if self.api and self.api.efforts then
        return self.api:efforts(id)
    end
    return DEFAULT_EFFORTS
end

function Provider:images(id)
    local found = self:model(id)
    return found and found.images
end

function Provider:budget(id)
    local found = self:model(id)
    local window = found and found.context or self.context_window
    if not window then
        return nil
    end
    local reserve = math.min(found and found.output or MAX_RESERVE, math.floor(window / 4))
    return { window = window, reserve = reserve }
end

function Provider:apply(patch)
    for _, key in ipairs({ "name", "api", "base_url", "auth_env", "oauth", "context_window" }) do
        if patch[key] ~= nil then
            self[key] = patch[key]
        end
    end
    for _, entry in ipairs(models(patch.models)) do
        local replaced = false
        for index, existing in ipairs(self.models) do
            if existing.id == entry.id then
                self.models[index] = entry
                replaced = true
            end
        end
        if not replaced then
            self.models[#self.models + 1] = entry
        end
    end
end

local function create(spec)
    return setmetatable({
        id = spec.id,
        name = spec.name,
        api = spec.api,
        base_url = spec.base_url,
        auth_env = spec.auth_env or {},
        oauth = spec.oauth,
        context_window = spec.context_window,
        models = models(spec.models),
        owner = plugin.current(),
    }, Provider)
end

function M.get(id)
    for _, provider in ipairs(M.providers) do
        if provider.id == id then
            return provider
        end
    end
end

function M.by_name(name)
    for _, provider in ipairs(M.providers) do
        if provider.name == name then
            return provider
        end
    end
end

function M.all()
    return M.providers
end

function M.add(patch)
    if type(patch) ~= "table" or type(patch.id) ~= "string" then
        error("uji.provider.add needs a table with an id", 2)
    end
    for key in pairs(patch) do
        if not FIELDS[key] then
            error("unknown field `" .. tostring(key) .. "` in provider " .. patch.id, 2)
        end
    end
    api(patch.api, patch.id)
    local existing = M.get(patch.id)
    if existing then
        existing:apply(patch)
        return
    end
    if not (patch.name and patch.api and patch.base_url) then
        error("provider `" .. patch.id .. "` is new, so it needs a name, an api and a base_url", 2)
    end
    M.providers[#M.providers + 1] = create(patch)
end

function M.remove(id)
    for index, provider in ipairs(M.providers) do
        if provider.id == id then
            table.remove(M.providers, index)
            return true
        end
    end
    return false
end

function M.drop_owner(_, owner)
    local kept = {}
    for _, provider in ipairs(M.providers) do
        if provider.owner ~= owner then
            kept[#kept + 1] = provider
        end
    end
    M.providers = kept
end

plugin.track(M)

return M
