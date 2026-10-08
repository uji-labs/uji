local host = require("uji.core.ui.host")
local ito = require("ito")

return ito.view(function()
    local ui = host.Host.current
    local ctx = ito.theme()
    local styles = ctx.styles
    local line = ui.composer.line
    local composing = ui:composing()
    local around = ctx.limits.input_rows + 1
    local anchor = composing and line.cursor or 0
    local from = ito.text.line_start(line.text, anchor, around)
    local near = line.text:sub(from + 1, ito.text.line_end(line.text, anchor, around))
    local shown = { { near } }
    if composing then
        shown = ctx:typed({ text = near, cursor = line.cursor - from }, { text = styles.input, cursor = styles.cursor })
    end
    return ito.HStack({
        ito.Text(ctx.symbols.input):style(styles.accent):repeating(),
        ito.Text(shown):style(styles.input):wrap():grow():max_height(ctx.limits.input_rows),
    }):spacing(1)
end)
