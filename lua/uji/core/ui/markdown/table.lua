local ito = require("ito")
local list = require("uji.utils.list")

local function row(ctx, line, columns)
    local styles = ctx.styles
    local cells = {}
    for index, cell in ipairs(line.cells) do
        if index > 1 then
            cells[#cells + 1] = ito.Text(ctx.symbols.column):style(styles.muted):padding({ horizontal = 1 }):repeating()
        end
        local spans = cell
        if line.head then
            spans = list.mapped(cell, function(span)
                return { span[1], (span[2] or styles.plain):merge(styles.table_head) }
            end)
        end
        local text = ito.Text(spans):wrap():shrink()
        cells[#cells + 1] = index == columns and text:grow() or text
    end
    return ito.GridRow(cells)
end

return ito.view(function(props)
    local ctx = ito.theme()
    local columns = 0
    for _, line in ipairs(props.rows) do
        columns = math.max(columns, #line.cells)
    end
    return ito.HStack({
        ito.Spacer():width(2),
        ito.Grid(list.mapped(props.rows, function(line)
            return row(ctx, line, columns)
        end)):grow(),
    })
end)
