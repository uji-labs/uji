local auth = require("uji.auth")
local catalog = require("uji.catalog")
local model = require("uji.model")
local notices = require("uji.notices")
local Prompt = require("uji.ui.views.prompt")
local Select = require("uji.ui.views.select")
local ui = require("uji.ui")

local SUBSCRIPTION = "Subscription (sign in with browser)"
local API_KEY = "API key"

local function configure(provider, url)
    model.set_setting("llm.provider", provider.id)
    if url then
        model.set_setting("llm.base_url", url.base_url)
        model.remember(provider.id, url.model)
    else
        model.set_setting("llm.base_url", "")
        model.remember(provider.id, model.model_for(provider))
    end
    model.resolve()
    notices.push("logged in to " .. provider.id)
end

local function ask_url()
    local base_url = ui:ask(Prompt({ title = "base_url" }))
    if base_url == nil then
        return nil
    end
    local chosen = ui:ask(Prompt({ title = "model" }))
    if chosen == nil then
        return nil
    end
    return { base_url = base_url, model = chosen }
end

local function ask_key(provider)
    local env = provider.auth_env or {}
    local title = #env == 0 and "api_key" or table.concat(env, " or ")
    local key = ui:ask(Prompt({ title = title .. " (enter to skip)", hidden = true }))
    if key == nil then
        return false
    end
    if key ~= "" then
        local saved, err = auth.save_key(provider.id, key)
        if not saved then
            notices.push("failed to save credential: " .. tostring(err))
        end
    end
    return true
end

return function()
    local names = {}
    for index, provider in ipairs(catalog.all()) do
        names[index] = provider.name
    end
    local name = ui:ask(Select({ title = "Provider", items = names }))
    local provider = name and catalog.by_name(name)
    if not provider then
        return
    end
    local needs_url = (provider.base_url or "") == ""
    if provider.oauth then
        local method = ui:ask(Select({ title = provider.name .. " sign-in", items = { SUBSCRIPTION, API_KEY } }))
        if method == SUBSCRIPTION then
            configure(provider, needs_url and { base_url = "", model = "" } or nil)
            auth.login(provider, model.resolve)
        elseif method == API_KEY and ask_key(provider) then
            configure(provider, needs_url and { base_url = "", model = "" } or nil)
        end
        return
    end
    local url
    if needs_url then
        url = ask_url()
        if not url then
            return
        end
    end
    if #(provider.auth_env or {}) == 0 and not needs_url then
        return configure(provider)
    end
    if ask_key(provider) then
        configure(provider, url)
    end
end
