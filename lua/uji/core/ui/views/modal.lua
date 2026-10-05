local class = require("uji.core.class")
local keys = require("uji.core.ui.keys")
local sys = require("uji.sys")

local EDITING = {
    backspace = "backspace",
    left = "cursor_left",
    right = "cursor_right",
    home = "cursor_start",
    ["end"] = "cursor_end",
}

local MOVES = { up = "modal_up", down = "modal_down" }

local Modal = class()

function Modal.navigate(chord, ui)
    local action = MOVES[chord.key]
    if action then
        ui:act(action)
    end
    return action ~= nil
end

Modal.mode = "select"

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

function Modal:selection()
    local modal = self
    return setmetatable({}, {
        __index = function(_, key)
            if key == "value" then
                return modal.cursor
            end
        end,
        __newindex = function(_, key, value)
            if key == "value" then
                modal.cursor = value
            end
        end,
    })
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

function Modal:view()
    return nil
end

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
