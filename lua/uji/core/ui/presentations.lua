local host = require("uji.core.ui.host")
local Input = require("uji.core.ui.input")
local ito = require("ito")
local sys = require("uji.sys")

local FULL = 100
local PLAIN = ito.TextStyle({})

local M = {}

function M.backdrop(view, ctx)
    local style = ctx.styles.screen
    if style == PLAIN then
        return view
    end
    return view:background(style)
end

M.Presentation = ito.view(function(props)
    local ui, modal = host.Host.current, props.modal
    local view = modal:view(ui, ito.theme(), props.room)
    if not view then
        return nil
    end
    local content = ito.VStack({ view })
    if props.fills then
        view:grow()
        content:grow()
    end
    local placement = ito.ToolbarPlacement
    local sheet = ito.ToolbarHost(ito.VStack({
        ito.HStack({
            ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
            ito.Spacer(),
            ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
        }),
        content,
        ito.ToolbarItems(placement.bottom_bar),
    })):focus_scope(modal)
    if props.clears then
        M.backdrop(sheet:opaque(), ito.theme())
    end
    return sheet
end)

local function guarded(ui)
    return {
        failed = function(problem)
            ui:report("modal_failure", "modal: " .. sys.message(problem))
        end,
    }
end

local function layers(ui, modals, build)
    local out = {}
    for index, modal in ipairs(modals) do
        out[index] = ito.SubcomposeLayout(function(room)
            return build(modal, room)
        end, guarded(ui))
            :id(modal)
            :hidden(index < #modals)
    end
    return out
end

M.Composer = ito.view(function()
    local ui = host.Host.current
    local takeovers = ui:takeovers()
    if #takeovers == 0 then
        return Input()
    end
    return ito.VStack(layers(ui, takeovers, function(modal, room)
        return M.Presentation({ modal = modal, room = room })
    end))
end)

M.Modals = ito.view(function()
    local ui = host.Host.current
    return ito.VStack(layers(ui, ui:inlines(), function(modal, room)
        return ito.VStack({ ito.Spacer(), M.Presentation({ modal = modal, room = room, clears = true }) })
    end)):preference(host.Hosted, true)
end)

M.Floating = ito.view(function(props)
    local ui, limits = host.Host.current, ito.theme().limits
    local floats = ui:floats(props.hosted)
    return ito.SubcomposeLayout(function(screen)
        local width = math.floor(screen.width * limits.float_width / FULL)
        local height = math.floor(screen.height * limits.float_height / FULL)
        local shown = layers(ui, floats, function(modal, room)
            return M.Presentation({ modal = modal, room = room, clears = true, fills = true })
        end)
        for index, layer in ipairs(shown) do
            layer:width(width):height(height)
            if floats[index] ~= ui.modal then
                layer:hidden()
            end
        end
        return ito.ZStack(shown)
    end):grow()
end)

return M
