local host = require("uji.core.ui.host")
local ito = require("ito")
local list = require("uji.utils.list")
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
    local open = props.open.value
    local expanded = open[props.id] == true
    local scroll = host.Host.current.scroll
    local toggle = ito.remember(function()
        return toggler(props.open, props.id, scroll)
    end, props.open, props.id, scroll)
    local answers = props.answers or {}
    local marks = list.mapped(answers, function(answer)
        if not answer then
            return "-"
        end
        return open[answer.id] and "1" or "0"
    end)
    local views = ito.remember(function()
        local results = list.mapped(answers, function(answer)
            return answer
                and {
                    message = answer.message,
                    expanded = open[answer.id] == true,
                    toggle = toggler(props.open, answer.id, scroll),
                }
        end)
        return rows.entry(ctx, props.message, props.gap, props.thinking, props.custom, expanded, toggle, results)
    end, ctx, props.message, props.gap, props.thinking, props.custom, expanded, toggle, table.concat(marks))
    return ito.Group(views)
end)
