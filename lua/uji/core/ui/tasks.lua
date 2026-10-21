local host = require("uji.core.ui.host")
local ito = require("ito")
local list = require("uji.utils.list")

return ito.view(function()
    local ui = host.Host.current
    local rows, hint = ui.tasks, ui.hint
    local ctx = ito.theme()
    if #rows == 0 then
        if not hint then
            return nil
        end
        return ito.Text(hint.text):style(ctx.styles.dim):padding({ leading = 1 })
    end
    return ito.VStack(list.mapped(rows, function(task)
        local selected = ui.selected == task.id
        local live = task.state == "running"
        return ito.HStack({
            ito.Text(ctx.symbols.pointer):style(ctx.styles.confirm_selected):padding({ trailing = 1 }):invisible(not selected),
            ito.Text(live and ctx.symbols.running or ctx.symbols.failed):style(live and ctx.styles.accent or ctx.styles.error),
            ito.Text(" " .. task.name):style(ctx.styles.accent),
            ito.Text("  " .. task.detail):style(ctx.styles.muted):grow(),
            ito.Text(task.elapsed .. "s"):style(ctx.styles.dim):padding({ trailing = 1 }),
        })
    end))
end)
