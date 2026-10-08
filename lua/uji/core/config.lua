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
local FLAGS = { "config-dir", "data-dir", "db" }

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
    local init = config and sys.fs.join(config, paths.INIT_FILE)
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
    sys.os.restart({ args = args, roots = declared })
    return true
end

function M.reload()
    local app = require("uji.core.app")
    if app.agent and app.agent:working() then
        notices.push("finish or interrupt the current turn before reloading")
        return
    end
    local argv = { app.argv[1] or "uji", "resume", "--id", app.session.id }
    for _, flag in ipairs(FLAGS) do
        local value = app.flags[flag]
        if value then
            argv[#argv + 1] = "--" .. flag
            argv[#argv + 1] = value
        end
    end
    local draft = require("uji.core.ui").composer:text()
    sys.os.restart({ args = argv, roots = packs.expected(), carry = sys.json.encode({ draft = draft }) })
end

return M
