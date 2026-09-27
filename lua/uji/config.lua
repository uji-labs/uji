local catalog = require("uji.catalog")
local context = require("uji.context")
local discover = require("uji.agent.discover")
local event = require("uji.event")
local model = require("uji.model")
local notices = require("uji.notices")
local packs = require("uji.packs")
local paths = require("uji.paths")
local plugin = require("uji.plugin")
local sys = require("uji.sys")
local tool = require("uji.tool")

local DEFAULTS = "uji.defaults"

local M = { searching = false }

local function source(path, name)
    local ok, err = pcall(plugin.source, path, name)
    if not ok then
        notices.push(path .. ": " .. tostring(err))
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
    require("uji.wires")
    catalog.load(require("uji.providers"))
    require("uji.tools")
    local init = config and config .. "/" .. paths.INIT_FILE
    package.loaded[DEFAULTS] = nil
    if init and sys.fs.stat(init) then
        source(init, "init")
    else
        local ok, err = pcall(plugin.run, "defaults", nil, require, DEFAULTS)
        if not ok then
            notices.push(DEFAULTS .. ": " .. tostring(err))
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
    discover.start(function()
        event.emit("status_changed", {})
    end)
    event.emit("status_changed", {})
end

function M.reload()
    for _, loaded in ipairs(plugin.list()) do
        plugin.unload(loaded.name)
    end
    packs.reset()
    tool.reset()
    context.reset()
    require("uji.ui"):reset()
    M.load()
    M.refresh()
end

return M
