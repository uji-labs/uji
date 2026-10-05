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
    local styles = ctx.styles
    return ito.Lines(function(width)
        local lines = {}
        for index, row in ipairs(input:shown(ui, draft, width)) do
            if row.after then
                lines[index] = { { row.before, styles.input }, { ctx.symbols.cursor, styles.cursor }, { row.after, styles.input } }
            else
                lines[index] = { { row.before, styles.input } }
            end
        end
        return lines
    end)
end)
