local Flash = require("uji.core.ui.flash")
local host = require("uji.core.ui.host")
local ito = require("ito")
local presentations = require("uji.core.ui.presentations")
local screens = require("uji.core.ui.screen")
local sys = require("uji.sys")

local M = {}

local Root = ito.view(function(props)
    local ui = props.ui
    local screen = props.plain and screens.Screen.body(screens.slots) or screens.Screen(screens.slots)
    local main = ito.ToolbarHost(screen)
    for _, declared in ipairs(ui.toolbars) do
        main:toolbar(declared.items)
    end
    local root = ito.ZStack({
        alignment = ito.Alignment.top_leading,
        main:overlay_preference_value(host.Hosted, function(hosted)
            return presentations.Floating({ hosted = hosted })
        end):grow(),
        ito.SelectionHighlight(),
        Flash():align(ito.Alignment.top_trailing),
    })
    return presentations.backdrop(root, ito.theme())
end)

function M.frame(ui)
    local window, ctx = ui.window, ui.theme:context()
    ctx.width, ctx.height = ui.screen:size()
    local ok, root, frame = pcall(window.place, window, host.Host:provide(ui, Root({ ui = ui })), ctx)
    if ok then
        ui.screen_failure = nil
    else
        ui:report("screen_failure", "screen: " .. sys.message(root))
        root, frame = window:place(host.Host:provide(ui, Root({ ui = ui, plain = true })), ctx)
    end
    return window:draw(root, frame)
end

function M.show(ui, element)
    local screen = ui:open()
    screen:clear()
    local ctx = ui.theme:context()
    ito.Window(screen, function() end):render(host.Host:provide(ui, presentations.backdrop(element, ctx)), ctx)
end

return M
