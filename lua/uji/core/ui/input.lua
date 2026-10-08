local host = require("uji.core.ui.host")
local Input = require("uji.core.ui.views.input")
local ito = require("ito")
local list = require("uji.utils.list")

return ito.view(function()
    local ui = host.Host.current
    local ctx = ito.theme()
    local input = ito.remember(function()
        return Input()
    end)
    local line = ui.composer.line
    local draft = { text = line.text, cursor = line.cursor, revision = line.revision, focused = ui:composing() }
    local styles = ctx.styles
    return ito.HStack({
        ito.Text(ctx.symbols.input):style(styles.accent):repeating(),
        ito.Lines(function(width)
            return list.mapped(input:shown(ui, draft, math.max(width, 1)), function(row)
                local spans = { { row.before, styles.input } }
                if row.after then
                    spans[2] = { ctx.symbols.cursor, styles.cursor }
                    spans[3] = { row.after, styles.input }
                end
                return spans
            end)
        end):grow(),
    })
end)
