local sys = require("uji.sys")

local M = {
    INIT_FILE = "init.lua",
    MODULE_DIR = "lua",
    PLUGIN_DIR = "plugin",
    overrides = {},
}

local function absolute(path)
    return path and path:sub(1, 1) == "/"
end

local function dir(own, xdg, fallback)
    local set = sys.os.env(own)
    if set then
        return set
    end
    local base = sys.os.env(xdg)
    if absolute(base) then
        return base .. "/uji"
    end
    local home = sys.os.env("HOME")
    if home then
        return home .. "/" .. fallback .. "/uji"
    end
end

function M.config()
    return M.overrides.config or dir("UJI_CONFIG_DIR", "XDG_CONFIG_HOME", ".config")
end

function M.data()
    return M.overrides.data or dir("UJI_DATA_DIR", "XDG_DATA_HOME", ".local/share")
end

function M.site()
    local data = M.data()
    return data and data .. "/site"
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
    return data and data .. "/uji.db"
end

function M.expand(path)
    local home = sys.os.env("HOME")
    if home and path:sub(1, 2) == "~/" then
        return home .. path:sub(2)
    end
    return path
end

return M
