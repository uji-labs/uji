local auth = require("uji.auth")
local catalog = require("uji.catalog")
local model = require("uji.model")
local notices = require("uji.notices")
local Select = require("uji.ui.views.select")
local ui = require("uji.ui")

return function()
    local current = model.setting("llm.provider") or ""
    local available = {}
    for _, provider in ipairs(catalog.all()) do
        if #provider.models > 0 and (provider.id == current or auth.authenticated(provider)) then
            available[#available + 1] = provider
        end
    end
    if #available == 0 then
        notices.push("Please run /login to configure a provider")
        return
    end
    local qualify = #available > 1
    local items, choices = {}, {}
    for _, provider in ipairs(available) do
        for _, entry in ipairs(provider.models) do
            local label = qualify and provider.name .. " · " .. entry.id or entry.id
            choices[label] = { provider = provider.id, model = entry.id }
            items[#items + 1] = label
        end
    end
    local title = qualify and "Models" or available[1].name .. " models"
    local choice = ui:ask(Select({ title = title, items = items }))
    local picked = choice and choices[choice]
    if not picked then
        return
    end
    if model.setting("llm.provider") ~= picked.provider then
        model.set_setting("llm.provider", picked.provider)
        model.set_setting("llm.base_url", "")
    end
    model.remember(picked.provider, picked.model)
    model.resolve()
end
