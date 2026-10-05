local class = require("uji.core.class")
local text = require("ito").text

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

function Input:layout(ui, draft, width, height)
    local focused = draft.focused
    local tokens = ui.theme.tokens
    local margin = math.max(height or 0, tokens.limits.input_rows) + 1
    local key = table.concat({ draft.revision, draft.cursor, width, margin, tostring(focused), ui.theme.revision }, ":")
    if self.key == key then
        return self.cached
    end
    local anchor = focused and draft.cursor or 0
    local from = text.line_start(draft.text, anchor, margin)
    local shown = draft.text:sub(from + 1, text.line_end(draft.text, anchor, margin))
    local display = text.chars(shown)
    local cursor = text.length(shown:sub(1, draft.cursor - from))
    if focused then
        table.insert(display, cursor + 1, tokens.symbols.cursor)
    end
    self.key = key
    self.cached = {
        display = display,
        cursor = focused and cursor or nil,
        rows = text.ranges(display, width),
    }
    return self.cached
end

function Input:rows(ui, draft, width)
    return math.min(math.max(#self:layout(ui, draft, width).rows, 1), ui.theme.tokens.limits.input_rows)
end

function Input:shown(ui, draft, width)
    local height = self:rows(ui, draft, width)
    local shape = self:layout(ui, draft, width, height)
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
    local shown = {}
    for index = skip + 1, math.min(skip + height, #rows) do
        local row = rows[index]
        if cursor and cursor >= row[1] and cursor < row[2] then
            shown[#shown + 1] = { before = collect(display, row[1], cursor), after = collect(display, cursor + 1, row[2]) }
        else
            shown[#shown + 1] = { before = collect(display, row[1], row[2]) }
        end
    end
    if #shown == 0 then
        shown[1] = { before = "" }
    end
    return shown
end

return Input
