local canvas = require("uji.ui.canvas")
local class = require("uji.class")
local Modal = require("uji.ui.views.modal")
local text = require("uji.ui.text")

local MAX_ROWS = 10

local function collect(chars, from, to)
    local out = {}
    for index = from + 1, to do
        local char = chars[index]
        if char ~= "\n" then
            out[#out + 1] = char
        end
    end
    return table.concat(out)
end

local Input = class()

function Input:init()
    self.key = nil
end

function Input:layout(ui, width)
    local line = ui.composer.line
    local focused = ui.modal == nil
    local key = table.concat({ line.revision, line.cursor, width, tostring(focused) }, ":")
    if self.key == key then
        return self.cached
    end
    local display = text.chars(line.text)
    local cursor = text.length(line.text:sub(1, line.cursor))
    if focused then
        table.insert(display, cursor + 1, Modal.CURSOR)
    end
    self.key = key
    self.cached = {
        display = display,
        cursor = focused and cursor or nil,
        rows = text.ranges(display, width),
    }
    return self.cached
end

function Input:rows(ui, width)
    local modal = ui.modal
    if modal and modal.takeover then
        return modal:takeover_rows(ui, width)
    end
    return math.min(math.max(#self:layout(ui, width).rows, 1), MAX_ROWS)
end

function Input:draw(ui, screen, area, window)
    local inner = canvas.block(screen, area, ui:chrome(window))
    local modal = ui.modal
    if modal and modal.takeover then
        canvas.lines(screen, inner, modal:lines(ui, inner.width, inner.height))
        return
    end
    local palette = ui.palette
    local height = math.max(inner.height, 1)
    local shape = self:layout(ui, inner.width)
    local cursor, rows, display = shape.cursor, shape.rows, shape.display
    local cursor_row = 1
    if cursor then
        for index, row in ipairs(rows) do
            if cursor >= row[1] and cursor < row[2] then
                cursor_row = index
                break
            end
        end
    end
    local skip = math.max(cursor_row - height, 0)
    local lines = {}
    for index = skip + 1, math.min(skip + height, #rows) do
        local row = rows[index]
        if cursor and cursor >= row[1] and cursor < row[2] then
            lines[#lines + 1] = {
                { collect(display, row[1], cursor), palette.input },
                { Modal.CURSOR, palette.cursor },
                { collect(display, cursor + 1, row[2]), palette.input },
            }
        else
            lines[#lines + 1] = { { collect(display, row[1], row[2]), palette.input } }
        end
    end
    canvas.lines(screen, inner, lines)
end

return Input
