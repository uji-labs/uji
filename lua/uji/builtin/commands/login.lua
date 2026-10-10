local list = require("uji.utils.list")

local SUBSCRIPTION = "Subscription (sign in with browser)"
local API_KEY = "API key"
local SIGN_IN = "Sign in again"
local SIGN_OUT = "Sign out"

local function configure(provider, url)
    uji.model.use({ provider = provider.id, base_url = url and url.base_url or "", model = url and url.model })
    uji.notify("logged in to " .. provider.id)
end

local function ask_url()
    local base_url = uji.ui.prompt({ title = "base_url" })
    if base_url == nil then
        return nil
    end
    local chosen = uji.ui.prompt({ title = "model" })
    if chosen == nil then
        return nil
    end
    return { base_url = base_url, model = chosen }
end

local function ask_key(provider)
    local env = provider.auth_env
    local title = #env == 0 and "api_key" or table.concat(env, " or ")
    local key = uji.ui.prompt({ title = title .. " (enter to skip)", hidden = true })
    if key == nil then
        return false
    end
    if key ~= "" then
        local saved, err = uji.auth.save_key(provider.id, key)
        if not saved then
            uji.notify("failed to save credential: " .. tostring(err))
        end
    end
    return true
end

local function sign_in(provider)
    local ok, err = uji.auth.login(provider.id)
    if ok then
        uji.notify("signed in to " .. provider.id)
    else
        uji.notify("sign-in failed: " .. tostring(err))
    end
end

local function sign_out(provider)
    local removed, err = uji.auth.remove(provider.id)
    if removed == nil then
        uji.notify("failed to sign out: " .. tostring(err))
    elseif removed then
        uji.notify("signed out of " .. provider.id)
    else
        uji.notify(provider.id .. " uses the key in " .. table.concat(provider.auth_env, " or ") .. ", so unset it to sign out")
    end
end

local function chosen(name)
    for _, provider in ipairs(uji.provider.list()) do
        if provider.name == name then
            return provider
        end
    end
end

uji.command.add("login", {
    desc = "configure provider and auth",
    handler = function()
        local names = list.mapped(uji.provider.list(), function(provider)
            return provider.name
        end)
        local name = uji.ui.select({ title = "Provider", items = names })
        local provider = name and chosen(name)
        if not provider then
            return
        end
        if uji.auth.authenticated(provider.id) then
            local action = uji.ui.select({ title = provider.name, items = { SIGN_IN, SIGN_OUT } })
            if action == SIGN_OUT then
                return sign_out(provider)
            elseif action ~= SIGN_IN then
                return
            end
        end
        if provider.loop then
            return configure(provider)
        end
        local needs_url = provider.base_url == ""
        local blank = needs_url and { base_url = "", model = "" } or nil
        if provider.oauth then
            local method = uji.ui.select({ title = provider.name .. " sign-in", items = { SUBSCRIPTION, API_KEY } })
            if method == SUBSCRIPTION then
                configure(provider, blank)
                sign_in(provider)
            elseif method == API_KEY and ask_key(provider) then
                configure(provider, blank)
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
        if #provider.auth_env == 0 and not needs_url then
            return configure(provider)
        end
        if ask_key(provider) then
            configure(provider, url)
        end
    end,
})
