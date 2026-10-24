local Credentials = require("uji.core.auth.credentials")
local check = require("uji.core.check")
local device = require("uji.core.auth.device")
local notices = require("uji.core.notices")
local oauth = require("uji.core.auth.oauth")
local paths = require("uji.core.paths")
local process = require("uji.core.system.process")
local task = require("uji.core.task")

local OPTIONS = { keychain = "boolean", file = "string" }

local M = { options = { keychain = false } }

function M.credentials()
    if not M.store then
        M.store = Credentials(paths.data())
        M.store.keychain = M.options.keychain
        M.store.auth_file = M.options.file
    end
    return M.store
end

function M.configure(opts)
    check.options(opts, "uji.auth.configure")
    for key, value in pairs(opts) do
        local wanted = OPTIONS[key]
        if not wanted then
            error("unknown key " .. tostring(key), 2)
        end
        if type(value) ~= wanted then
            error(key .. " must be a " .. wanted, 2)
        end
        M.options[key] = value
    end
    if M.store then
        M.store.keychain = M.options.keychain
        M.store.auth_file = M.options.file
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

local function session_credential(provider, credential)
    if not oauth.expired(credential) then
        return credential
    end
    local refresh = provider.oauth.refresh or oauth.refresh
    local refreshed = refresh(provider.oauth, credential)
    local saved, err = M.credentials():save(provider.id, refreshed)
    if not saved then
        error("refreshed the session but could not save it: " .. tostring(err), 0)
    end
    return refreshed
end

function M.resolve(provider)
    local credentials = M.credentials()
    local stored = credentials:get(provider.id)
    local key = stored and stored.type == "api_key" and stored.key or credentials:env_key(provider)
    local session
    if provider.oauth and stored and stored.type == "oauth" then
        local ok, credential = pcall(session_credential, provider, stored)
        if not ok then
            return nil, { kind = "provider", message = tostring(credential) }
        end
        session = {
            token = credential.access,
            base_url = credential.base_url,
            account_id = credential.account_id,
            headers = provider.oauth.request_headers or {},
            identity_prompt = provider.oauth.identity_prompt,
        }
    end
    return { key = key, oauth = session }
end

local function browser_login(config)
    local flow, server = oauth.start(config)
    local url = flow:url()
    process.open(url)
    notices.push("opened your browser to sign in - " .. url)
    return oauth.login(config, flow, server)
end

local function device_login(config, present)
    local handler = config.device.start and config.device or device
    local flow = handler.start(config)
    notices.push("open " .. flow.url .. " and enter code " .. flow.code .. " to sign in")
    if present then
        local canceled = present(flow)
        local winner, credential = task.race(function()
            return handler.login(config, flow)
        end, canceled)
        if winner == 2 then
            error("sign-in canceled", 0)
        end
        return credential
    end
    return handler.login(config, flow)
end

local METHODS = { browser = browser_login, device = device_login }

function M.login(provider, opts, present)
    opts = opts or {}
    check.options(opts, "uji.auth.login")
    for key in pairs(opts) do
        if key ~= "method" then
            error("unknown key " .. tostring(key), 2)
        end
    end
    local config = provider.oauth
    local method = opts.method or (config and not config.authorize_url and "device" or "browser")
    local sign_in = METHODS[method]
    if not sign_in then
        error("uji.auth.login method must be browser or device", 2)
    end
    if not config then
        return nil, "this provider does not support subscription sign-in"
    end
    if method == "device" and not config.device then
        return nil, "this provider does not support device code sign-in"
    end
    if method == "browser" and not config.authorize_url then
        return nil, "this provider does not support browser sign-in"
    end
    local signed, grant = pcall(sign_in, config, present)
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
