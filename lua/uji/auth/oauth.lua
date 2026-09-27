local class = require("uji.class")
local sys = require("uji.sys")
local task = require("uji.task")

local CALLBACK_TIMEOUT = 300
local READ_TIMEOUT = 5
local EXPIRY_SKEW = 300
local MAX_ERROR_BODY = 500
local LAUNCHERS = { macos = "open", windows = "explorer", linux = "xdg-open", other = "xdg-open" }

local M = {}

local function encode(value)
    return (tostring(value):gsub("[^%w%-%._~]", function(char)
        return string.format("%%%02X", char:byte())
    end))
end

local function decode(value)
    return (value:gsub("%+", " "):gsub("%%(%x%x)", function(code)
        return string.char(tonumber(code, 16))
    end))
end

local function pairs_text(pairs_list)
    local out = {}
    for index, pair in ipairs(pairs_list) do
        out[index] = encode(pair[1]) .. "=" .. encode(pair[2])
    end
    return table.concat(out, "&")
end

local function query(text)
    local out = {}
    for pair in (text or ""):gmatch("[^&]+") do
        local key, value = pair:match("^([^=]*)=(.*)$")
        if key then
            out[decode(key)] = decode(value)
        end
    end
    return out
end

local function clip(body)
    local trimmed = body:match("^%s*(.-)%s*$")
    local count = 0
    for at in trimmed:gmatch("()[^\128-\191]") do
        count = count + 1
        if count > MAX_ERROR_BODY then
            return trimmed:sub(1, at - 1) .. "…"
        end
    end
    return trimmed
end

local function token()
    return sys.base64.encode(sys.random(32), { url = true, pad = false })
end

local function html(message)
    return message:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

local function respond(conn, status, message)
    local body = '<!doctype html><meta charset=utf-8><title>uji</title>'
        .. '<body style="font:16px system-ui;padding:3rem;color:#111">'
        .. html(message)
        .. "</body>"
    conn:write(
        "HTTP/1.1 " .. status .. "\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: "
            .. #body
            .. "\r\nConnection: close\r\n\r\n"
            .. body
    )
    conn:close()
end

function M.now()
    return math.floor(sys.os.now() / 1000)
end

function M.expired(credential)
    return (credential.expires_at or 0) ~= 0 and M.now() >= credential.expires_at
end

function M.open_browser(url)
    local launcher = LAUNCHERS[sys.os.platform] or "xdg-open"
    local proc = sys.proc.spawn({ launcher, url })
    if proc then
        task.spawn(function()
            proc:wait()
        end)
    end
end

local Flow = class()

function Flow:init(config)
    self.config = config
    self.verifier = token()
    self.challenge = sys.base64.encode(sys.sha256(self.verifier), { url = true, pad = false })
    self.state = config.state == "verifier" and self.verifier or token()
    self.redirect_uri = "http://localhost:" .. config.redirect_port .. config.redirect_path
end

function Flow:url()
    local params = {
        { "client_id", self.config.client_id },
        { "response_type", "code" },
        { "redirect_uri", self.redirect_uri },
        { "scope", self.config.scopes },
        { "code_challenge", self.challenge },
        { "code_challenge_method", "S256" },
        { "state", self.state },
    }
    local extra = {}
    for key, value in pairs(self.config.authorize_params or {}) do
        extra[#extra + 1] = { key, value }
    end
    table.sort(extra, function(left, right)
        return left[1] < right[1]
    end)
    for _, pair in ipairs(extra) do
        params[#params + 1] = pair
    end
    return self.config.authorize_url .. "?" .. pairs_text(params)
end

function Flow:serve(conn)
    local line = conn:line(READ_TIMEOUT)
    local target = line and line:match("^%S+%s+(%S+)")
    if not target then
        conn:close()
        return nil
    end
    local path, rest = target:match("^([^?]*)%??(.*)$")
    if path ~= self.config.redirect_path then
        respond(conn, "404 Not Found", "Unknown callback path.")
        return nil
    end
    local params = query(rest)
    if params.error then
        respond(conn, "400 Bad Request", params.error)
        return nil
    end
    if not params.code then
        respond(conn, "400 Bad Request", "Missing authorization code.")
        return nil
    end
    respond(conn, "200 OK", "Signed in. You can close this tab and return to uji.")
    return params
end

function Flow:wait(server)
    local finished, params = task.timeout(CALLBACK_TIMEOUT, function()
        while true do
            local conn, err = server:accept()
            if not conn then
                error("cannot listen on 127.0.0.1:" .. self.config.redirect_port .. " for the oauth callback: " .. tostring(err), 0)
            end
            local found = self:serve(conn)
            if found then
                return found
            end
        end
    end)
    if not finished then
        error("timed out waiting for the browser to complete sign-in", 0)
    end
    return params
end

local function post(config, endpoint, fields)
    local request = { method = "POST", url = config.token_url, headers = {} }
    if config.token_body == "json" then
        local body = {}
        for _, pair in ipairs(fields) do
            body[pair[1]] = pair[2]
        end
        request.headers["Content-Type"] = "application/json"
        request.body = sys.json.encode(body)
    else
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = pairs_text(fields)
    end
    local response, err = sys.net.request(request)
    if not response then
        error("http: " .. tostring(err), 0)
    end
    if response.status < 200 or response.status >= 300 then
        error(endpoint .. " returned " .. response.status .. ": " .. clip(response.body), 0)
    end
    local ok, parsed = pcall(sys.json.decode, response.body, { nulls = false })
    if not ok or type(parsed) ~= "table" or type(parsed.access_token) ~= "string" then
        error(endpoint .. " returned an unexpected body: " .. clip(response.body), 0)
    end
    return parsed
end

local function tokens(parsed)
    local expires = parsed.expires_in or 0
    return {
        type = "oauth",
        access = parsed.access_token,
        refresh = parsed.refresh_token or "",
        expires_at = expires > 0 and M.now() + expires - EXPIRY_SKEW or 0,
    }
end

local function trade(config, exchange, parsed)
    local subject = exchange.subject == "access_token" and parsed.access_token or (parsed.id_token or "")
    return post(config, "api key exchange", {
        { "grant_type", exchange.grant_type },
        { "client_id", config.client_id },
        { "requested_token", exchange.requested_token },
        { "subject_token", subject },
        { "subject_token_type", exchange.subject_token_type },
    }).access_token
end

function M.start(config)
    local flow = Flow(config)
    local server, err = sys.net.listen(config.redirect_port)
    if not server then
        error("cannot listen on 127.0.0.1:" .. config.redirect_port .. " for the oauth callback: " .. tostring(err), 0)
    end
    return flow, server
end

function M.login(config, flow, server)
    local ok, params = pcall(flow.wait, flow, server)
    server:close()
    if not ok then
        error(params, 0)
    end
    if params.state and params.state ~= flow.state then
        error("oauth state mismatch; the sign-in was not completed in this session", 0)
    end
    local fields = {
        { "grant_type", "authorization_code" },
        { "client_id", config.client_id },
        { "code", params.code or "" },
        { "redirect_uri", flow.redirect_uri },
        { "code_verifier", flow.verifier },
    }
    if config.state == "verifier" then
        fields[#fields + 1] = { "state", flow.state }
    end
    local parsed = post(config, "token exchange", fields)
    if config.exchange then
        return { type = "api_key", key = trade(config, config.exchange, parsed) }
    end
    return tokens(parsed)
end

function M.refresh(config, refresh_token)
    local refreshed = tokens(post(config, "token refresh", {
        { "grant_type", "refresh_token" },
        { "client_id", config.client_id },
        { "refresh_token", refresh_token },
    }))
    if refreshed.refresh == "" then
        refreshed.refresh = refresh_token
    end
    return refreshed
end

return M
