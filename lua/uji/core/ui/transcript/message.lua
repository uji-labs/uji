local host = require("uji.core.ui.host")
local ito = require("ito")
local rows = require("uji.core.ui.transcript.rows")
local tables = require("uji.core.tables")

local function toggler(open, id, scroll)
    return function()
        open.value = tables.with(open.value, id, not open.value[id] or nil)
        scroll.following = false
    end
end

return ito.view(function(props)
    local ctx = ito.theme()
    local expanded = props.open.value[props.id] == true
    local scroll = host.Host.current.scroll
    local toggle = ito.remember(function()
        return toggler(props.open, props.id, scroll)
    end, props.open, props.id, scroll)
    local views = ito.remember(function()
        return rows.entry(ctx, props.message, props.gap, props.thinking, props.custom, expanded, toggle)
    end, ctx, props.message, props.gap, props.thinking, props.custom, expanded, toggle)
    return ito.Group(views)
end)
