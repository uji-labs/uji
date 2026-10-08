local sys = require("uji.sys")

local M = {
    INIT_FILE = "init.lua",
    MODULE_DIR = "lua",
    NATIVE_DIR = "native",
    PLUGIN_DIR = "plugin",
    overrides = {},
}

local function dir(own, xdg, fallback)
    local set = sys.os.env(own)
    if set then
        return set
    end
    local base = sys.os.env(xdg)
    if base and sys.fs.absolute(base) then
        return sys.fs.join(base, "uji")
    end
    local home = sys.os.home()
    if home then
        return sys.fs.join(home, unpack(fallback))
    end
end

function M.config()
    return M.overrides.config or dir("UJI_CONFIG_DIR", "XDG_CONFIG_HOME", { ".config", "uji" })
end

function M.data()
    return M.overrides.data or dir("UJI_DATA_DIR", "XDG_DATA_HOME", { ".local", "share", "uji" })
end

function M.site()
    local data = M.data()
    return data and sys.fs.join(data, "site")
end

function M.db()
    if M.overrides.db then
        return M.overrides.db
    end
    local set = sys.os.env("UJI_DB")
    if set then
        return set
    end
    local data = M.data()
    return data and sys.fs.join(data, "uji.db")
end

function M.expand(path)
    return sys.os.expand(path)
end

return M
