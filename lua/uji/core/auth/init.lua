local Credentials = require("uji.core.auth.credentials")
local check = require("uji.core.check")
local notices = require("uji.core.notices")
local oauth = require("uji.core.auth.oauth")
local paths = require("uji.core.paths")
local process = require("uji.core.system.process")

local M = { options = { keychain = false } }

function M.credentials()
    if not M.store then
        M.store = Credentials(paths.data())
        M.store.keychain = M.options.keychain
    end
    return M.store
end

function M.configure(opts)
    check.options(opts, "uji.auth.configure")
    for key, value in pairs(opts) do
        if key ~= "keychain" then
            error("unknown key " .. tostring(key), 2)
        end
        if type(value) ~= "boolean" then
            error("keychain must be a boolean", 2)
        end
        M.options.keychain = value
    end
    if M.store then
        M.store.keychain = M.options.keychain
    end
end

function M.save_key(provider_id, key)
    return M.credentials():save(provider_id, { type = "api_key", key = key })
end

function M.remove(provider_id)
    return M.credentials():remove(provider_id)
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

function M.login(provider)
    if not provider.oauth then
        return nil, "this provider does not support subscription sign-in"
    end
    local ok, flow, server = pcall(oauth.start, provider.oauth)
    if not ok then
        return nil, tostring(flow)
    end
    local url = flow:url()
    process.open(url)
    notices.push("opened your browser to sign in - " .. url)
    local signed, grant = pcall(oauth.login, provider.oauth, flow, server)
    if not signed then
        return nil, tostring(grant)
    end
    local saved, err = M.credentials():save(provider.id, grant)
    if not saved then
        return nil, "signed in but could not save the credential: " .. tostring(err)
    end
    return true
end

return M
