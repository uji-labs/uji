local diagnostics = require("uji.core.diagnostics")
local Flash = require("uji.core.ui.flash")
local host = require("uji.core.ui.host")
local ito = require("ito")
local presentations = require("uji.core.ui.presentations")
local screens = require("uji.core.ui.screen")

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
    local ok, root, frame = xpcall(window.place, diagnostics.capture, window, host.Host:provide(ui, Root({ ui = ui })), ctx)
    diagnostics.report("screen", not ok and root or nil)
    if not ok then
        root, frame = window:place(host.Host:provide(ui, Root({ ui = ui, plain = true })), ctx)
    end
    return window:draw(root, frame)
end

function M.show(ui, window, element)
    ui:open():clear()
    local ctx = ui.theme:context()
    window:render(host.Host:provide(ui, presentations.backdrop(element, ctx)), ctx)
end

return M
