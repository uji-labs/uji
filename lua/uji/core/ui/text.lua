local sys = require("uji.sys")

local M = {}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

M.CHAR = CHAR

local function ascii(text)
    return not text:find("[\128-\255]")
end

M.width = sys.width

function M.length(text)
    if ascii(text) then
        return #text
    end
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

function M.chars(text)
    local out = {}
    for char in text:gmatch(CHAR) do
        out[#out + 1] = char
    end
    return out
end

function M.clip(text, width)
    if width <= 0 then
        return ""
    end
    if ascii(text) then
        return text:sub(1, width)
    end
    local used, out = 0, {}
    for char in text:gmatch(CHAR) do
        local size = M.width(char)
        if used + size > width then
            break
        end
        used = used + size
        out[#out + 1] = char
    end
    return table.concat(out)
end

function M.pad(text, width)
    local missing = width - M.width(text)
    if missing <= 0 then
        return text
    end
    return text .. string.rep(" ", missing)
end

function M.trim(text)
    return text:match("^%s*(.-)%s*$")
end

function M.lines(source)
    local out = {}
    if source == "" then
        return out
    end
    local text = source:sub(-1) == "\n" and source or source .. "\n"
    for line in text:gmatch("(.-)\n") do
        out[#out + 1] = line:sub(-1) == "\r" and line:sub(1, -2) or line
    end
    return out
end

local Row = {}
Row.__index = Row

local function row(width, out)
    return setmetatable({ width = width, out = out, parts = {}, used = 0 }, Row)
end

function Row:flush()
    if #self.parts > 0 then
        self.out[#self.out + 1] = table.concat(self.parts)
        self.parts = {}
        self.used = 0
    end
end

function Row:push(text, size)
    self.parts[#self.parts + 1] = text
    self.used = self.used + size
end

function Row:word(word, size)
    if self.used + 1 + size > self.width then
        self:flush()
    elseif self.used > 0 then
        self:push(" ", 1)
    end
    self:push(word, size)
end

function Row:letters(word)
    for char in word:gmatch(CHAR) do
        local size = M.width(char)
        if self.used + size > self.width then
            self:flush()
        end
        self:push(char, size)
    end
end

local function wrap_line(line, width, out)
    if M.width(line) <= width then
        out[#out + 1] = line
        return
    end
    local current = row(width, out)
    for word in line:gmatch("%S+") do
        local size = M.width(word)
        if size > width then
            current:flush()
            current:letters(word)
        else
            current:word(word, size)
        end
    end
    current:flush()
end

function M.wrap(source, width)
    local out = {}
    if width <= 0 then
        return M.lines(source)
    end
    for _, line in ipairs(M.lines(source)) do
        wrap_line(line, width, out)
    end
    return out
end

local function fold(chars, start, finish, width, rows)
    local newline = finish > start and chars[finish] == "\n"
    local content = newline and finish - 1 or finish
    local at = start
    local pushed = #rows
    while at < content do
        local hard = math.min(at + width, content)
        if hard == content then
            rows[#rows + 1] = { at, content }
            break
        end
        local stop = hard
        for index = hard, at + 1, -1 do
            if chars[index] == " " then
                stop = index
                break
            end
        end
        rows[#rows + 1] = { at, stop }
        at = stop
    end
    if #rows == pushed then
        rows[#rows + 1] = { start, start }
    end
    if newline then
        rows[#rows][2] = finish
    end
end

function M.ranges(chars, width)
    if width <= 0 or #chars == 0 then
        return { { 0, #chars } }
    end
    local rows = {}
    local start = 0
    for index = 1, #chars do
        if chars[index] == "\n" then
            fold(chars, start, index, width, rows)
            start = index
        end
    end
    if start < #chars or chars[#chars] == "\n" then
        fold(chars, start, #chars, width, rows)
    end
    return rows
end

return M
