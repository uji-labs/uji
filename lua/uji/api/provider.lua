local catalog = require("uji.core.catalog")
local task = require("uji.core.task")

local function model_row(entry)
    return {
        id = entry.id,
        context = entry.context,
        output = entry.output,
        reasoning = entry.reasoning,
        cache = entry.cache,
        images = entry.images,
        efforts = entry.efforts and { unpack(entry.efforts) },
    }
end

local function model_rows(provider)
    local rows = {}
    for index, entry in ipairs(provider.models) do
        rows[index] = model_row(entry)
    end
    return rows
end

local function provider_row(provider)
    return {
        id = provider.id,
        name = provider.name,
        api = provider.api,
        base_url = provider.base_url,
        auth_env = { unpack(provider.auth_env) },
        oauth = provider.oauth ~= nil,
        loop = provider.loop ~= nil,
        context_window = provider.context_window,
        models = model_rows(provider),
        state = provider.state,
        error = provider.error,
    }
end

local function found(id)
    local provider = catalog.get(id)
    if not provider then
        error("no provider is registered as " .. tostring(id), 3)
    end
    return provider
end

uji.provider = {
    STATE = catalog.STATE,
    add = catalog.add,
    remove = catalog.remove,
    list = function()
        local rows = {}
        for index, provider in ipairs(catalog.all()) do
            rows[index] = provider_row(provider)
        end
        return rows
    end,
    get = function(id)
        local provider = catalog.get(id)
        return provider and provider_row(provider)
    end,
    load = task.callback(function(id)
        local provider = found(id)
        provider:load()
        return provider_row(provider)
    end),
}
