local plugin = require("uji.plugin")

local MAX_RESERVE = 20000

local FIELDS = {
    id = true,
    name = true,
    wire = true,
    base_url = true,
    compat = true,
    auth_env = true,
    oauth = true,
    context_window = true,
    models = true,
}

local M = { providers = {} }

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
    }
end

local function models(list)
    local out = {}
    for index, spec in ipairs(list or {}) do
        out[index] = model(spec)
    end
    return out
end

local function copy(table_value)
    local out = {}
    for key, value in pairs(table_value or {}) do
        out[key] = value
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
    self.origin = "registered"
    for _, key in ipairs({ "name", "wire", "base_url", "auth_env", "oauth", "context_window" }) do
        if patch[key] ~= nil then
            self[key] = patch[key]
        end
    end
    if patch.compat ~= nil then
        if type(self.compat) == "table" and type(patch.compat) == "table" then
            for key, value in pairs(patch.compat) do
                self.compat[key] = value
            end
        else
            self.compat = patch.compat
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

local function create(spec, origin)
    return setmetatable({
        id = spec.id,
        name = spec.name,
        wire = spec.wire,
        base_url = spec.base_url,
        compat = copy(spec.compat),
        auth_env = spec.auth_env or {},
        oauth = spec.oauth,
        context_window = spec.context_window,
        models = models(spec.models),
        origin = origin,
        owner = plugin.current(),
    }, Provider)
end

function M.load(specs)
    M.providers = {}
    for index, spec in ipairs(specs) do
        M.providers[index] = create(spec, "builtin")
    end
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
    local existing = M.get(patch.id)
    if existing then
        existing:apply(patch)
        return
    end
    if not (patch.name and patch.wire and patch.base_url) then
        error("provider `" .. patch.id .. "` is new, so it needs a name, a wire and a base_url", 2)
    end
    M.providers[#M.providers + 1] = create(patch, "registered")
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
        if provider.owner ~= owner or provider.origin ~= "registered" then
            kept[#kept + 1] = provider
        end
    end
    M.providers = kept
end

function M.set_windows(id, windows)
    local provider = M.get(id)
    if not provider then
        return 0
    end
    local changed = 0
    for _, found in ipairs(windows) do
        local entry = provider:model(found.model)
        if entry and not (entry.context == found.context and entry.output == found.output) then
            entry.context = found.context or entry.context
            entry.output = found.output or entry.output
            changed = changed + 1
        end
    end
    return changed
end

plugin.track(M)

return M
