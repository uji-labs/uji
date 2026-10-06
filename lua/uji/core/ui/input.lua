local host = require("uji.core.ui.host")
local Input = require("uji.core.ui.views.input")
local ito = require("ito")

return ito.view(function()
    local ui = host.Host.current
    local ctx = ito.theme()
    local input = ito.remember(function()
        return Input()
    end)
    local line = ui.composer.line
    local draft = { text = line.text, cursor = line.cursor, revision = line.revision, focused = ui:composing() }
    local styles, prefix = ctx.styles, ctx.symbols.input
    return ito.Lines(function(width)
        local lines = {}
        for index, row in ipairs(input:shown(ui, draft, math.max(width - ctx:measure(prefix), 1))) do
            local spans = { { prefix, styles.accent }, { row.before, styles.input } }
            if row.after then
                spans[3] = { ctx.symbols.cursor, styles.cursor }
                spans[4] = { row.after, styles.input }
            end
            lines[index] = spans
        end
        return lines
    end)
end)
