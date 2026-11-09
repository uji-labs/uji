local oauth = require("uji.core.auth.oauth")
local sys = require("uji.sys")
local task = require("uji.core.task")
local version = require("uji.version")

local M = {}

function M.headers(token)
    return {
        Accept = "application/json",
        Authorization = token and "Bearer " .. token,
        ["User-Agent"] = "uji",
        ["Editor-Version"] = "uji/" .. version,
        ["Editor-Plugin-Version"] = "uji/" .. version,
        ["Copilot-Integration-Id"] = "vscode-chat",
    }
end

function M.request(url, body, token)
    local headers = M.headers(token)
    headers["Content-Type"] = body and "application/json" or nil
    local response, err = sys.net.request({
        url = url,
        method = body and "POST" or "GET",
        headers = headers,
        body = body and sys.json.encode(body),
        timeout = 30,
    })
    if not response then
        error("Copilot request failed: " .. tostring(err), 0)
    end
    if response.status < 200 or response.status >= 300 then
        error("Copilot request returned " .. response.status .. "; check your subscription or sign in again", 0)
    end
    local ok, value = pcall(sys.json.decode, response.body, { nulls = false })
    if not ok or type(value) ~= "table" then
        error("Copilot request returned an unexpected body", 0)
    end
    return value
end

local function text(value)
    return type(value) == "string" and value ~= ""
end

local function positive(value)
    return type(value) == "number" and value > 0 and value < math.huge
end

function M.refresh(config, credential)
    local body = M.request(config.token_url, nil, credential.refresh)
    if not text(body.token) or not positive(body.expires_at) or body.expires_at <= oauth.now() then
        error("Copilot token request returned an unexpected body", 0)
    end
    local base_url = body.endpoints and body.endpoints.api
    if base_url ~= nil and (not text(base_url) or not base_url:match("^https?://")) then
        error("Copilot token request returned an invalid API endpoint", 0)
    end
    return {
        type = "oauth",
        access = body.token,
        refresh = credential.refresh,
        expires_at = math.max(oauth.now() + 1, body.expires_at - 60),
        base_url = base_url or credential.base_url,
    }
end

function M.start(config)
    local body = M.request(config.device.code_url, { client_id = config.client_id, scope = "read:user" })
    if
        not text(body.device_code)
        or not text(body.user_code)
        or not text(body.verification_uri)
        or not positive(body.interval)
        or not positive(body.expires_in)
    then
        error("Copilot device code request returned an unexpected body", 0)
    end
    return {
        id = body.device_code,
        code = body.user_code,
        url = body.verification_uri,
        interval = body.interval,
        expires_at = sys.os.clock() + body.expires_in,
    }
end

function M.login(config, flow)
    local remaining = flow.expires_at - sys.os.clock()
    local expired = "Copilot device code expired; start sign-in again"
    if remaining <= 0 then
        error(expired, 0)
    end
    local finished, credential = task.timeout(remaining, function()
        while true do
            sys.sleep(flow.interval)
            local body = M.request(config.device.poll_url, {
                client_id = config.client_id,
                device_code = flow.id,
                grant_type = "urn:ietf:params:oauth:grant-type:device_code",
            })
            if text(body.access_token) then
                return M.refresh(config, { refresh = body.access_token })
            elseif body.error == "slow_down" then
                flow.interval = math.max(flow.interval + 5, positive(body.interval) and body.interval or 0)
            elseif body.error ~= "authorization_pending" then
                error("Copilot sign-in failed: " .. tostring(body.error or "unexpected token response"), 0)
            end
        end
    end)
    if not finished then
        error(expired, 0)
    end
    return credential
end

return M
