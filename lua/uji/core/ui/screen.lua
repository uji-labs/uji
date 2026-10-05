local Activity = require("uji.core.ui.activity")
local ito = require("ito")
local presentations = require("uji.core.ui.presentations")
local Transcript = require("uji.core.ui.transcript")

local M = {}

M.slots = {
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
        screen.transcript():grow(),
        screen.activity():padding({ vertical = 1 }),
        screen.modals(),
        ito.ToolbarItems(placement.keyboard),
        screen.composer():border(ito.theme().borders.plain, { edges = ito.Edges.horizontal }),
        ito.ToolbarItems(placement.bottom_bar),
    })
end)

return M
