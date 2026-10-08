local class = require("uji.core.class")
local sys = require("uji.sys")

local SERVICE = "uji"
local FILE = "auth.toml"
local PRIVATE = tonumber("600", 8)

local Credentials = class()

function Credentials:init(directory)
    self.directory = directory
    self.keychain = false
end

local function entry(value)
    if type(value) == "string" then
        return { type = "api_key", key = value }
    end
    if type(value) == "table" and value.type then
        return value
    end
end

local function parse(raw)
    local ok, credential = pcall(sys.json.decode, raw, { nulls = false })
    if ok and type(credential) == "table" and credential.type then
        return credential
    end
    return { type = "api_key", key = raw }
end

function Credentials:path()
    return self.directory and sys.fs.join(self.directory, FILE)
end

function Credentials:file()
    local path = self:path()
    local text = path and sys.fs.read(path)
    if not text then
        return {}
    end
    local ok, all = pcall(sys.toml.decode, text)
    if not ok then
        return nil, path .. " could not be read: " .. sys.message(all)
    end
    return all
end

function Credentials:get(provider)
    if self.keychain then
        local raw = sys.keychain.get(SERVICE, provider)
        if raw then
            return parse(raw)
        end
    end
    local all, err = self:file()
    if not all then
        return nil, err
    end
    return entry(all[provider])
end

function Credentials:key(provider)
    local credential = self:get(provider)
    return credential and credential.type == "api_key" and credential.key or nil
end

function Credentials:save(provider, credential)
    if self.keychain and sys.keychain.set(SERVICE, provider, sys.json.encode(credential)) then
        return credential
    end
    local path = self:path()
    if not path then
        return nil, "no data directory to keep the credential in"
    end
    local all, err = self:file()
    if not all then
        return nil, err
    end
    all[provider] = credential
    sys.fs.mkdir(self.directory)
    local written, failure = sys.fs.write(path, sys.toml.encode(all), { mode = PRIVATE })
    if not written then
        return nil, failure
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
