local layout = require("uji.core.ui.layout")

local M = {}

local BOXES = {
    plain = { "┌", "┐", "└", "┘", "─", "│" },
    rounded = { "╭", "╮", "╰", "╯", "─", "│" },
}

function M.write(screen, row, col, line, width)
    if width > 0 and row >= 0 and col >= 0 then
        screen:line(row, col, line, width)
    end
end

function M.clear(screen, area)
    if area.width > 0 and area.height > 0 then
        screen:fill(area.y, area.x, area.width, area.height)
    end
end

function M.popup(screen, area, rows, height)
    local popup = layout.rect(area.x, area.y + area.height - height, area.width, height)
    M.clear(screen, popup)
    M.lines(screen, popup, rows)
end

function M.lines(screen, area, rows)
    for index = 1, math.min(#rows, area.height) do
        M.write(screen, area.y + index - 1, area.x, rows[index], area.width)
    end
end

function M.block(screen, area, opts)
    local border = opts.border or "none"
    if area.width <= 0 or area.height <= 0 then
        return layout.inner(area, border, opts.padding)
    end
    if opts.style and opts.style ~= 0 then
        screen:paint(area.y, area.x, area.width, area.height, opts.style)
    end
    local box = BOXES[border]
    local bottom = area.y + area.height - 1
    if box then
        local rule = string.rep(box[5], math.max(area.width - 2, 0))
        M.write(screen, area.y, area.x, box[1] .. rule .. box[2], area.width)
        for row = area.y + 1, bottom - 1 do
            M.write(screen, row, area.x, box[6], 1)
            M.write(screen, row, area.x + area.width - 1, box[6], 1)
        end
        if bottom > area.y then
            M.write(screen, bottom, area.x, box[3] .. rule .. box[4], area.width)
        end
    elseif border == "horizontal" then
        local rule = string.rep("─", area.width)
        M.write(screen, area.y, area.x, rule, area.width)
        if bottom > area.y then
            M.write(screen, bottom, area.x, rule, area.width)
        end
    end
    if opts.title and border ~= "none" then
        local side = box and 1 or 0
        M.write(screen, area.y, area.x + side, opts.title, area.width - side * 2)
    end
    return layout.inner(area, border, opts.padding)
end

return M
