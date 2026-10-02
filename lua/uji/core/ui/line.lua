local class = require("uji.core.class")
local text = require("uji.core.ui.text")

local function continuation(byte)
    return byte ~= nil and byte >= 128 and byte < 192
end

local function prev_boundary(value, index)
    if index <= 0 then
        return 0
    end
    local at = index - 1
    while at > 0 and continuation(value:byte(at + 1)) do
        at = at - 1
    end
    return at
end

local function next_boundary(value, index)
    if index >= #value then
        return #value
    end
    local at = index + 1
    while at < #value and continuation(value:byte(at + 1)) do
        at = at + 1
    end
    return at
end

local function char_before(value, at)
    if at <= 0 then
        return nil
    end
    return value:sub(prev_boundary(value, at) + 1, at)
end

local function char_at(value, at)
    if at >= #value then
        return nil
    end
    return value:sub(at + 1, next_boundary(value, at))
end

local function is_word(char)
    return #char > 1 or char:match("^[%w_]$") ~= nil
end

local function is_space(char)
    return char:match("^%s$") ~= nil
end

local Line = class()

function Line:init(value)
    self.text = value or ""
    self.cursor = #self.text
    self.kill = ""
    self.revision = 0
end

function Line:touch()
    self.revision = self.revision + 1
end

function Line:splice(from, to, with)
    self.text = self.text:sub(1, from) .. (with or "") .. self.text:sub(to + 1)
end

function Line:empty()
    return self.text == ""
end

function Line:set(value)
    self.text = value
    self.cursor = #value
    self:touch()
end

function Line:clear()
    self.text = ""
    self.cursor = 0
    self:touch()
end

function Line:take()
    local taken = self.text
    self.text = ""
    self.cursor = 0
    self:touch()
    return taken
end

function Line:insert(value)
    self:splice(self.cursor, self.cursor, value)
    self.cursor = self.cursor + #value
    self:touch()
end

function Line:backspace()
    if self.cursor == 0 then
        return
    end
    self:erase_back_to(prev_boundary(self.text, self.cursor))
end

function Line:delete_before(bytes)
    local from = math.max(self.cursor - bytes, 0)
    while from > 0 and continuation(self.text:byte(from + 1)) do
        from = from - 1
    end
    self:erase_back_to(from)
end

function Line:erase_back_to(from)
    self:splice(from, self.cursor)
    self.cursor = from
    self:touch()
end

function Line:delete_forward()
    if self.cursor >= #self.text then
        return
    end
    self:splice(self.cursor, next_boundary(self.text, self.cursor))
    self:touch()
end

function Line:left()
    self.cursor = prev_boundary(self.text, self.cursor)
end

function Line:right()
    self.cursor = next_boundary(self.text, self.cursor)
end

function Line:home()
    self.cursor = self:line_start(self.cursor)
end

function Line:tail()
    self.cursor = self:line_end(self.cursor)
end

function Line:word_left()
    self.cursor = self:word_start_before(self.cursor)
end

function Line:word_right()
    self.cursor = self:word_end_after(self.cursor)
end

function Line:delete_word_back()
    local at = self.cursor
    local char = char_before(self.text, at)
    while char and is_space(char) do
        at = at - #char
        char = char_before(self.text, at)
    end
    while char and not is_space(char) do
        at = at - #char
        char = char_before(self.text, at)
    end
    self:kill_range(at, self.cursor)
    self.cursor = at
end

function Line:delete_word_forward()
    self:kill_range(self.cursor, self:word_end_after(self.cursor))
end

function Line:delete_to_start()
    local from = self:line_start(self.cursor)
    self:kill_range(from, self.cursor)
    self.cursor = from
end

function Line:delete_to_end()
    self:kill_range(self.cursor, self:line_end(self.cursor))
end

function Line:yank()
    if self.kill == "" then
        return
    end
    local killed = self.kill
    self:insert(killed)
    self.kill = killed
end

function Line:transpose()
    local value = self.text
    local at_end = self.cursor >= #value or char_at(value, self.cursor) == "\n"
    local right = at_end and self.cursor or next_boundary(value, self.cursor)
    local mid = at_end and prev_boundary(value, right) or self.cursor
    local left = prev_boundary(value, mid)
    if left == mid or mid == right then
        return
    end
    self:splice(left, right, value:sub(mid + 1, right) .. value:sub(left + 1, mid))
    self.cursor = right
    self:touch()
end

function Line:up()
    local start = self:line_start(self.cursor)
    if start == 0 then
        return false
    end
    local column = text.length(self.text:sub(start + 1, self.cursor))
    local above = start - 1
    self.cursor = self:column_offset(self:line_start(above), above, column)
    return true
end

function Line:down()
    local finish = self:line_end(self.cursor)
    if finish >= #self.text then
        return false
    end
    local column = text.length(self.text:sub(self:line_start(self.cursor) + 1, self.cursor))
    local below = finish + 1
    self.cursor = self:column_offset(below, self:line_end(below), column)
    return true
end

function Line:kill_range(from, to)
    if from >= to then
        return
    end
    self.kill = self.text:sub(from + 1, to)
    self:splice(from, to)
    self:touch()
end

function Line:line_start(at)
    return self.text:sub(1, at):find("\n[^\n]*$") or 0
end

function Line:line_end(at)
    local found = self.text:find("\n", at + 1, true)
    return found and found - 1 or #self.text
end

function Line:column_offset(start, finish, column)
    local at = start
    for _ = 1, column do
        if at >= finish then
            return finish
        end
        at = next_boundary(self.text, at)
    end
    return math.min(at, finish)
end

function Line:word_start_before(at)
    local char = char_before(self.text, at)
    while char and not is_word(char) do
        at = at - #char
        char = char_before(self.text, at)
    end
    while char and is_word(char) do
        at = at - #char
        char = char_before(self.text, at)
    end
    return at
end

function Line:word_end_after(at)
    local char = char_at(self.text, at)
    while char and not is_word(char) do
        at = at + #char
        char = char_at(self.text, at)
    end
    while char and is_word(char) do
        at = at + #char
        char = char_at(self.text, at)
    end
    return at
end

return Line
