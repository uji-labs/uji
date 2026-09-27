local class = require("uji.class")
local keys = require("uji.ui.keys")
local sys = require("uji.sys")
local text = require("uji.ui.text")

local CURSOR = "█"
local MASK = "•"

local EDITING = {
    backspace = "backspace",
    left = "cursor_left",
    right = "cursor_right",
    home = "cursor_start",
    ["end"] = "cursor_end",
}

local Modal = class()

Modal.mode = "select"
Modal.CURSOR = CURSOR

function Modal.typed(line, hidden, style, cursor)
    local value = line.text
    local before, after
    if hidden then
        local at = text.length(value:sub(1, line.cursor))
        before = string.rep(MASK, at)
        after = string.rep(MASK, text.length(value) - at)
    else
        before = value:sub(1, line.cursor)
        after = value:sub(line.cursor + 1)
    end
    return { { before, style }, { CURSOR, cursor }, { after, style } }
end

function Modal.step(cursor, delta, count)
    if count == 0 then
        return 1
    end
    if delta == -1 and cursor <= 1 then
        return count
    end
    if delta == 1 and cursor >= count then
        return 1
    end
    return math.min(math.max(cursor + delta, 1), count)
end

function Modal:init()
    self.answer = sys.promise()
end

function Modal:settle(value)
    if not self.answer.settled then
        self.answer:resolve(value)
    end
    if self.ui then
        self.ui:close_modal(self)
    end
end

function Modal:wait()
    return self.answer:await()
end

function Modal:close()
    self:settle(nil)
end

function Modal:accept()
    self:settle(nil)
end

function Modal:cancel()
    self:settle(nil)
end

function Modal:line()
    return nil
end

function Modal:edited() end

function Modal:move() end

function Modal:rows()
    return nil
end

function Modal:draw() end

function Modal:edit_key(chord, ui)
    if keys.typed(chord) then
        ui:insert(chord.key)
        return true
    end
    local action = EDITING[chord.key]
    if action then
        ui:act(action)
        return true
    end
    return false
end

function Modal:key(chord, ui)
    if chord.key == "esc" then
        ui:act("modal_cancel")
    elseif chord.key == "enter" then
        ui:act("modal_accept")
    else
        self:edit_key(chord, ui)
    end
end

return Modal
