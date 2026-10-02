local catalog = require("uji.core.catalog")

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

local function provider_row(provider)
    local models = {}
    for index, entry in ipairs(provider.models) do
        models[index] = model_row(entry)
    end
    return {
        id = provider.id,
        name = provider.name,
        api = provider.api,
        base_url = provider.base_url,
        auth_env = { unpack(provider.auth_env) },
        oauth = provider.oauth ~= nil,
        context_window = provider.context_window,
        models = models,
    }
end

uji.provider = {
    add = catalog.add,
    remove = catalog.remove,
    list = function()
        local rows = {}
        for index, provider in ipairs(catalog.all()) do
            rows[index] = provider_row(provider)
        end
        return rows
    end,
}
