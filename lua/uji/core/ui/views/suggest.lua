local class = require("uji.core.class")
local keys = require("uji.core.ui.keys")
local Modal = require("uji.core.ui.views.modal")

local Suggest = class(Modal)

Suggest.mode = "suggest"

function Suggest:init(items)
    Modal.init(self)
    self:set(items)
end

function Suggest:set(items)
    self.items = items
    self.cursor = 1
end

function Suggest:move(delta)
    self.cursor = Modal.step(self.cursor, delta, #self.items)
end

function Suggest:chosen()
    local item = self.items[self.cursor]
    return item and item.name
end

function Suggest:accept()
    local ui = self.ui
    local name = self:chosen()
    if name then
        ui.composer:set("/" .. name)
    end
    self:settle(nil)
    ui:submit()
end

function Suggest:cancel()
    self.ui.composer:clear()
    self:settle(nil)
end

function Suggest:complete()
    local name = self:chosen()
    if name then
        self.ui.composer:set("/" .. name .. " ")
        self:settle(nil)
    end
end

function Suggest:key(chord, ui)
    if Modal.navigate(chord, ui) then
        return
    end
    local key = chord.key
    if key == "tab" then
        ui:act("suggest_complete")
    elseif key == "esc" or key == "enter" then
        Modal.key(self, chord, ui)
    elseif keys.typed(chord) then
        ui:insert(key)
    elseif key == "backspace" then
        ui:act("backspace")
    end
end

function Suggest:view(_, ctx, area)
    if #self.items == 0 or area.height <= 0 then
        return nil
    end
    local data = { items = self.items, selection = self:selection(), height = area.height }
    return ctx:element("suggest", data, area.width)
end

return Suggest
