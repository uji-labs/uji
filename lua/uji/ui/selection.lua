local class = require("uji.class")
local text = require("uji.ui.text")

local MULTI_CLICK = 0.5
local JOINERS = { ["/"] = true, ["-"] = true, ["_"] = true, ["."] = true }

local function point(x, y)
    return { x = x, y = y }
end

local function before(a, b)
    return a.y < b.y or (a.y == b.y and a.x <= b.x)
end

local function alphanumeric(char)
    return #char > 1 or char:match("^%w$") ~= nil
end

local function segments(chars)
    local out = {}
    local at = 0
    while at < #chars do
        local start = at
        local char = chars[at + 1]
        if JOINERS[char] then
            at = at + 1
            out[#out + 1] = { start = start, finish = at, wordlike = true, joiner = true }
        else
            local wordlike = alphanumeric(char)
            while at < #chars and alphanumeric(chars[at + 1]) == wordlike and not JOINERS[chars[at + 1]] do
                at = at + 1
            end
            out[#out + 1] = { start = start, finish = at, wordlike = wordlike, joiner = false }
        end
    end
    return out
end

local function joins(left, right)
    return left.wordlike and right.wordlike and (left.joiner or right.joiner)
end

local Selection = class()

function Selection:init()
    self.rows = {}
    self.pending = nil
    self.range = nil
    self.grain = "char"
    self.initial = nil
    self.last = nil
end

function Selection:row(y)
    return self.rows[y] or {}
end

function Selection:line_span(y)
    return { start = 0, finish = #self:row(y) }
end

function Selection:word_span(at)
    local parts = segments(self:row(at.y))
    local found
    for index, part in ipairs(parts) do
        if at.x >= part.start and at.x < part.finish then
            found = index
            break
        end
    end
    if not found then
        return { start = at.x, finish = at.x + 1 }
    end
    local span = { start = parts[found].start, finish = parts[found].finish }
    local index = found
    while index > 1 and joins(parts[index - 1], parts[index]) do
        index = index - 1
        span.start = parts[index].start
    end
    index = found
    while index < #parts and joins(parts[index], parts[index + 1]) do
        index = index + 1
        span.finish = parts[index].finish
    end
    return span
end

function Selection:unit(at)
    if self.grain == "word" then
        return self:word_span(at)
    end
    if self.grain == "line" then
        return self:line_span(at.y)
    end
    return { start = at.x, finish = at.x + 1 }
end

function Selection:count(at, word, now)
    local last = self.last
    local count = 1
    if last and last.y == at.y and last.start == word.start and last.finish == word.finish and now - last.at < MULTI_CLICK then
        count = last.count % 3 + 1
    end
    self.last = { at = now, y = at.y, start = word.start, finish = word.finish, count = count }
    return count
end

function Selection:begin(at, now)
    local count = self:count(at, self:word_span(at), now)
    self.grain = count == 2 and "word" or count == 3 and "line" or "char"
    local span = self:unit(at)
    self.initial = span
    local head = self.grain == "char" and span.start or span.finish
    self.range = { anchor = point(span.start, at.y), head = point(head, at.y) }
end

function Selection:resolve()
    local pending = self.pending
    if pending then
        self.pending = nil
        self:begin(pending.at, pending.now)
    end
end

function Selection:active()
    return self.pending ~= nil or self.range ~= nil
end

function Selection:press(x, y, now)
    self.pending = { at = point(x, y), now = now }
end

function Selection:drag(x, y)
    self:resolve()
    local range = self.range
    if not range then
        return
    end
    local at = point(x, y)
    local initial = self.initial
    if self.grain == "char" or not initial then
        range.head = at
        return
    end
    local span = self:unit(at)
    local row = range.anchor.y
    if at.y < row or (at.y == row and span.finish <= initial.start) then
        self.range = { anchor = point(initial.finish, row), head = point(span.start, at.y) }
    else
        self.range = { anchor = point(initial.start, row), head = point(span.finish, at.y) }
    end
end

function Selection:bounds()
    local range = self.range
    if before(range.anchor, range.head) then
        return range.anchor, range.head
    end
    return range.head, range.anchor
end

function Selection:text()
    local start, finish = self:bounds()
    local out = {}
    for y = start.y, finish.y do
        local chars = self:row(y)
        local from = y == start.y and start.x or 0
        local to = y == finish.y and math.min(finish.x, #chars) or #chars
        local piece = table.concat(chars, "", from + 1, math.max(to, from))
        out[#out + 1] = piece:match("^(.-)%s*$")
    end
    return (table.concat(out, "\n"):gsub("^\n+", ""):gsub("\n+$", ""))
end

function Selection:release()
    self:resolve()
    if not self.range then
        return nil
    end
    local value = self:text()
    return value:find("%S") and value or nil
end

function Selection:clear()
    self.pending = nil
    self.initial = nil
    self.grain = "char"
    local had = self.range ~= nil
    self.range = nil
    return had
end

function Selection:sync(screen, width, height, style)
    if not self:active() then
        return
    end
    for y = 0, height - 1 do
        self.rows[y] = text.chars(screen:text(y) or "")
    end
    self:resolve()
    if not self.range then
        return
    end
    local start, finish = self:bounds()
    for y = start.y, math.min(finish.y, height - 1) do
        local from = y == start.y and start.x or 0
        local to = y == finish.y and finish.x or width
        if to > from then
            screen:paint(y, from, to - from, 1, style)
        end
    end
end

return Selection
