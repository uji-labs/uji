local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local styles = ctx.styles
    local spans = {}
    for index, cell in ipairs(props.cells) do
        if index > 1 then
            spans[#spans + 1] = { " " .. ctx.symbols.column .. " ", styles.muted }
        end
        for _, span in ipairs(cell) do
            spans[#spans + 1] = props.head and { span[1], (span[2] or styles.plain):merge(styles.table_head) } or span
        end
    end
    return ito.HStack({ ito.Spacer():width(2), ito.Text(spans):grow() })
end)
