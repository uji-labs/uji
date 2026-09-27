local Credentials = require("uji.auth.credentials")
local notices = require("uji.notices")
local oauth = require("uji.auth.oauth")
local paths = require("uji.paths")
local task = require("uji.task")

local M = {}

function M.credentials()
    if not M.store then
        local data = paths.data()
        M.store = Credentials(data and data .. "/auth.json")
    end
    return M.store
end

function M.save_key(provider_id, key)
    return M.credentials():save(provider_id, { type = "api_key", key = key })
end

function M.authenticated(provider)
    return M.credentials():authenticated(provider)
end

local function bearer(provider, credential)
    if not oauth.expired(credential) then
        return credential.access
    end
    local refreshed = oauth.refresh(provider.oauth, credential.refresh)
    local saved, err = M.credentials():save(provider.id, refreshed)
    if not saved then
        error("refreshed the session but could not save it: " .. tostring(err), 0)
    end
    return refreshed.access
end

function M.resolve(provider)
    local credentials = M.credentials()
    local stored = credentials:get(provider.id)
    local key = stored and stored.type == "api_key" and stored.key or Credentials.env_key(provider.auth_env)
    local session
    if provider.oauth and stored and stored.type == "oauth" then
        local ok, token = pcall(bearer, provider, stored)
        if not ok then
            return nil, { kind = "provider", message = tostring(token) }
        end
        session = {
            token = token,
            headers = provider.oauth.request_headers or {},
            identity_prompt = provider.oauth.identity_prompt,
        }
    end
    return { key = key, oauth = session }
end

function M.login(provider, on_done)
    if not provider.oauth then
        notices.push("sign-in failed: this provider does not support subscription sign-in")
        return
    end
    task.spawn(function()
        local ok, flow, server = pcall(oauth.start, provider.oauth)
        if not ok then
            notices.push("sign-in failed: " .. tostring(flow))
            return
        end
        local url = flow:url()
        oauth.open_browser(url)
        notices.push("opened your browser to sign in - " .. url)
        local signed, grant = pcall(oauth.login, provider.oauth, flow, server)
        if not signed then
            notices.push("sign-in failed: " .. tostring(grant))
            return
        end
        local saved, err = M.credentials():save(provider.id, grant)
        if not saved then
            notices.push("sign-in failed: signed in but could not save the credential: " .. tostring(err))
            return
        end
        notices.push("signed in to " .. provider.id)
        if on_done then
            on_done()
        end
    end)
end

return M
