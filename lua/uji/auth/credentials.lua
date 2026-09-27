local class = require("uji.class")
local sys = require("uji.sys")

local SERVICE = "uji"
local PRIVATE = tonumber("600", 8)

local Credentials = class()

function Credentials:init(path)
    self.path = path
end

local function parse(raw)
    local ok, credential = pcall(sys.json.decode, raw, { nulls = false })
    if ok and type(credential) == "table" and credential.type then
        return credential
    end
    return { type = "api_key", key = raw }
end

function Credentials:file()
    if not self.path then
        return {}
    end
    local text = sys.fs.read(self.path)
    if not text then
        return {}
    end
    local ok, all = pcall(sys.json.decode, text, { nulls = false })
    return ok and type(all) == "table" and all or {}
end

function Credentials:get(provider)
    local raw = sys.keychain.get(SERVICE, provider)
    if raw then
        return parse(raw)
    end
    return self:file()[provider]
end

function Credentials:key(provider)
    local credential = self:get(provider)
    return credential and credential.type == "api_key" and credential.key or nil
end

function Credentials:save(provider, credential)
    if sys.keychain.set(SERVICE, provider, sys.json.encode(credential)) then
        return credential
    end
    if not self.path then
        return nil, "no data directory to keep the credential in"
    end
    local all = self:file()
    all[provider] = credential
    local parent = self.path:match("^(.*)/[^/]*$")
    if parent then
        sys.fs.mkdir(parent)
    end
    local written, err = sys.fs.write(self.path, sys.json.encode(all), { mode = PRIVATE })
    if not written then
        return nil, err
    end
    return credential
end

function Credentials.env_key(names)
    for _, name in ipairs(names or {}) do
        local value = sys.os.env(name)
        if value then
            return value
        end
    end
end

function Credentials:authenticated(provider)
    return self:get(provider.id) ~= nil or Credentials.env_key(provider.auth_env) ~= nil
end

return Credentials
