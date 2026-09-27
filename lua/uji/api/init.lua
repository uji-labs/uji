local catalog = require("uji.catalog")
local command = require("uji.command")
local context = require("uji.context")
local event = require("uji.event")
local notices = require("uji.notices")
local plugin = require("uji.plugin")
local task = require("uji.task")
local tool = require("uji.tool")
local wire = require("uji.wire")

local M = {}

local function provider_row(provider)
    local models = {}
    for index, entry in ipairs(provider.models) do
        models[index] = { id = entry.id, context = entry.context, output = entry.output }
    end
    return {
        id = provider.id,
        name = provider.name,
        wire = provider.wire,
        base_url = provider.base_url,
        models = models,
    }
end

function M.install()
    uji.on = event.on
    uji.off = event.off
    uji.emit = event.emit
    uji.notify = notices.push
    uji.schedule = function(callback)
        task.schedule(callback)
    end
    uji.defer = function(seconds, callback)
        if type(seconds) ~= "number" or seconds < 0 then
            error("defer needs a number of seconds", 2)
        end
        return task.defer(seconds, callback)
    end

    uji.tool = {
        add = tool.add,
        remove = tool.remove,
        list = tool.list,
        enable = tool.enable,
        disable = tool.disable,
        policy = tool.policy,
        confine = tool.confine,
        roots = tool.roots,
    }

    uji.command = {
        add = command.add,
        remove = command.remove,
        list = command.list,
    }

    uji.context = {
        add = context.add,
        remove = context.remove,
        list = context.list,
        configure = context.configure,
    }

    uji.provider = {
        add = catalog.add,
        remove = catalog.remove,
        list = function()
            local rows = {}
            for index, provider in ipairs(catalog.all()) do
                rows[index] = provider_row(provider)
            end
            return rows
        end,
    }

    uji.wire = {
        add = wire.add,
        remove = wire.remove,
        list = wire.list,
    }

    uji.plugin = {
        list = plugin.list,
        unload = plugin.unload,
        reload = plugin.reload,
    }

    local packs = require("uji.packs")
    uji.pack = {
        add = packs.add,
        list = packs.list,
        update = packs.update,
    }

    uji.session = require("uji.api.session")
    uji.fs = require("uji.api.fs")
    uji.http = require("uji.api.http")
    uji.job = require("uji.api.job")
    require("uji.api.ui").install()
end

return M
