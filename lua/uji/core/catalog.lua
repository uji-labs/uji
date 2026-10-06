local check = require("uji.core.check")
local plugin = require("uji.core.plugin")
local sys = require("uji.sys")

local MAX_RESERVE = 20000
local EFFORTS = { "off", "minimal", "low", "medium", "high", "xhigh", "max" }
local DEFAULT_EFFORTS = { "off", "minimal", "low", "medium", "high" }

local FIELDS = {
    id = true,
    name = true,
    api = true,
    loop = true,
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

local STATE = { IDLE = "idle", LOADING = "loading", LOADED = "loaded", FAILED = "failed" }

local M = { providers = {}, EFFORTS = EFFORTS, DEFAULT_EFFORTS = DEFAULT_EFFORTS, STATE = STATE }

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
    local entry = {
        id = spec.id,
        context = spec.context,
        output = spec.output,
        reasoning = spec.reasoning == true,
        cache = spec.cache == true,
        efforts = efforts(spec.efforts, spec.id),
    }
    if type(spec.images) == "boolean" then
        entry.images = spec.images
    end
    return entry
end

local function api(value, id)
    if value ~= nil and (type(value) ~= "table" or type(value.stream) ~= "function") then
        error("the api of provider " .. id .. " needs a stream method", 0)
    end
    return value
end

local function loop(value, id)
    if value ~= nil and (not check.callable(value) or type(value.run) ~= "function") then
        error("the loop of provider " .. id .. " must be a class with a run method", 0)
    end
    return value
end

local function models(list)
    if list ~= nil and type(list) ~= "table" then
        error("models must be a list or a function that returns one", 0)
    end
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

function Provider:merge(list)
    for _, entry in ipairs(models(list)) do
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

function Provider:apply(patch)
    for _, key in ipairs({ "name", "api", "loop", "base_url", "auth_env", "oauth", "context_window" }) do
        if patch[key] ~= nil then
            self[key] = patch[key]
        end
    end
    if type(patch.models) == "function" then
        self.loader = patch.models
        self.state = STATE.IDLE
        self.error = nil
    else
        self:merge(patch.models)
    end
end

function Provider:load()
    if self.state == STATE.LOADED then
        return STATE.LOADED
    end
    local loading = self.loading
    if not loading then
        local loader = self.loader
        loading = sys.promise()
        self.loading = loading
        self.state = STATE.LOADING
        sys.task.spawn(function()
            local ok, err = pcall(function()
                self:merge(loader())
            end)
            local state, failure = ok and STATE.LOADED or STATE.FAILED, not ok and sys.message(err) or nil
            if self.loader == loader then
                self.state = state
                self.error = failure
            end
            self.loading = nil
            loading:resolve(state, failure)
        end)
    end
    return loading:await()
end

local function create(spec)
    local lazy = type(spec.models) == "function"
    return setmetatable({
        id = spec.id,
        name = spec.name,
        api = spec.api,
        loop = spec.loop,
        base_url = spec.base_url or "",
        auth_env = spec.auth_env or {},
        oauth = spec.oauth,
        context_window = spec.context_window,
        models = lazy and {} or models(spec.models),
        loader = lazy and spec.models or nil,
        state = lazy and STATE.IDLE or STATE.LOADED,
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
    loop(patch.loop, patch.id)
    local existing = M.get(patch.id)
    if existing then
        existing:apply(patch)
        return
    end
    if not (patch.name and patch.api and (patch.base_url or patch.loop)) then
        error("provider `" .. patch.id .. "` is new, so it needs a name, an api and a base_url or a loop", 2)
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
