local event = require("uji.core.event")
local model = require("uji.core.model")
local notices = require("uji.core.notices")
local packs = require("uji.core.packs")
local paths = require("uji.core.paths")
local plugin = require("uji.core.plugin")
local sys = require("uji.sys")
local tables = require("uji.core.tables")
local tool = require("uji.core.tool")

local DEFAULTS = "uji.builtin.defaults"

local M = { searching = false }

local function source(path, name)
    local ok, err = pcall(plugin.source, path, name)
    if not ok then
        notices.push(path .. ": " .. sys.message(err))
    end
end

function M.load()
    if not M.searching then
        table.insert(package.searchers, 2, packs.searcher)
        M.searching = true
    end
    local config = paths.config()
    if config then
        packs.add_root(config)
    end
    require("uji.builtin.providers")
    require("uji.builtin.tools")
    local init = config and config .. "/" .. paths.INIT_FILE
    package.loaded[DEFAULTS] = nil
    if init and sys.fs.stat(init) then
        source(init, "init")
    else
        local ok, err = pcall(plugin.run, "defaults", nil, require, DEFAULTS)
        if not ok then
            notices.push(DEFAULTS .. ": " .. sys.message(err))
        end
    end
    for _, root in ipairs(packs.list()) do
        for _, file in ipairs(packs.plugin_files(root)) do
            source(file)
        end
    end
    tool.compiled()
end

function M.refresh()
    model.resolve()
    event.emit("status_changed", {})
end

function M.settle(args)
    local declared = packs.overriding(packs.list())
    packs.remember(declared)
    if tables.same(declared, sys.os.roots) then
        return false
    end
    sys.os.restart({ args = args, roots = declared, carry = sys.os.carry })
    return true
end

function M.reload()
    local app = require("uji.core.app")
    local sessions = require("uji.core.ui.sessions")
    if sessions.busy() then
        notices.push("resolve pending work and queued messages before reloading")
        return
    end
    return sessions.restart(not app.session.pending and app.session or nil)
end

return M
