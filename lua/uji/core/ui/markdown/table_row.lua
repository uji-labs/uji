local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles = ctx.styles
    local line = { { "  " } }
    for index, cell in ipairs(props.cells) do
        if index > 1 then
            line[#line + 1] = { " " .. ctx.symbols.column .. " ", styles.muted }
        end
        for _, span in ipairs(cell) do
            line[#line + 1] = props.head and { span[1], (span[2] or styles.plain):merge(styles.table_head) } or span
        end
    end
    return ito.Lines({ line })
end)
