local host = require("uji.core.ui.host")
local ito = require("ito")
local list = require("uji.utils.list")

return ito.view(function()
    local jobs = host.Host.current.jobs
    local ctx = ito.theme()
    if #jobs.rows == 0 then
        if not jobs.hint then
            return nil
        end
        return ito.Text(jobs.hint.text):style(ctx.styles.dim):padding({ leading = 1 })
    end
    return ito.VStack(list.mapped(jobs.rows, function(row)
        local selected = jobs.selected == row.id
        local live = row.running
        return ito.HStack({
            ito.Text(ctx.symbols.pointer):style(ctx.styles.confirm_selected):padding({ trailing = 1 }):invisible(not selected),
            ito.Text(live and ctx.symbols.running or ctx.symbols.failed)
                :style(live and ctx.styles.accent or ctx.styles.error)
                :padding({ trailing = 1 }),
            ito.Text(row.name):style(ctx.styles.accent),
            ito.Text("  " .. row.detail):style(ctx.styles.muted):grow(),
            ito.Text(row.elapsed .. "s"):style(ctx.styles.dim):padding({ trailing = 1 }),
        })
    end))
end)
