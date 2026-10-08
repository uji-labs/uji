local Activity = require("uji.core.ui.activity")
local app = require("uji.core.app")
local Greeting = require("uji.core.ui.greeting")
local host = require("uji.core.ui.host")
local ito = require("ito")
local presentations = require("uji.core.ui.presentations")
local Transcript = require("uji.core.ui.transcript")

local M = {}

local Greeted = ito.view(function()
    local ui, session = host.Host.current, app.session
    if ui.sending() or ui.running or not ui.composer.line:empty() or (session ~= nil and #session:entries() > 0) then
        return nil
    end
    return Greeting()
end)

M.slots = {
    greeting = function()
        return Greeted()
    end,
    transcript = function()
        return Transcript()
    end,
    composer = function()
        return presentations.Composer()
    end,
    modals = function()
        return presentations.Modals()
    end,
    activity = function()
        return Activity()
    end,
}

M.Screen = ito.view(function(screen)
    local placement = ito.ToolbarPlacement
    return ito.VStack({
        ito.HStack({
            ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
            ito.Spacer(),
            ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
        }),
        screen.greeting(),
        screen.transcript():grow(),
        screen.activity():padding({ vertical = 1 }),
        screen.modals(),
        ito.ToolbarItems(placement.keyboard),
        screen.composer():border(ito.theme().borders.plain, { edges = ito.Edges.horizontal }),
        ito.ToolbarItems(placement.bottom_bar),
    })
end)

return M
