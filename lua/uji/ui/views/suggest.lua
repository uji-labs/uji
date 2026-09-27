local canvas = require("uji.ui.canvas")
local class = require("uji.class")
local keys = require("uji.ui.keys")
local layout = require("uji.ui.layout")
local Modal = require("uji.ui.views.modal")
local text = require("uji.ui.text")

local NAME_WIDTH = 12

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
    local key = chord.key
    if key == "up" then
        ui:act("modal_up")
    elseif key == "down" then
        ui:act("modal_down")
    elseif key == "tab" then
        ui:act("suggest_complete")
    elseif key == "esc" or key == "enter" then
        Modal.key(self, chord, ui)
    elseif keys.typed(chord) then
        ui:insert(key)
    elseif key == "backspace" then
        ui:act("backspace")
    end
end

function Suggest:visible(ui)
    return math.min(#self.items, math.max(ui.theme.suggest_max_height, 1))
end

function Suggest:rows(_, ui)
    local visible = self:visible(ui)
    return visible > 0 and visible or nil
end

function Suggest:draw(ui, screen, area)
    if #self.items == 0 or area.height <= 0 then
        return
    end
    local palette = ui.palette
    local visible = math.max(math.min(self:visible(ui), area.height), 1)
    local start = self.cursor > visible and self.cursor - visible or 0
    local lines = {}
    for at = start + 1, math.min(start + visible, #self.items) do
        local item = self.items[at]
        local chosen = at == self.cursor
        local name = "  " .. text.pad(item.name, NAME_WIDTH)
        local used = text.width(name) + text.width(item.desc)
        local pad = string.rep(" ", math.max(area.width - used, 0))
        if chosen then
            lines[#lines + 1] = { { name, palette.chosen_name }, { item.desc, palette.chosen_desc }, { pad, palette.selected } }
        else
            lines[#lines + 1] = { { name, palette.text }, { item.desc, palette.muted }, { pad, 0 } }
        end
    end
    local popup = layout.rect(area.x, area.y + area.height - #lines, area.width, #lines)
    canvas.clear(screen, popup)
    canvas.lines(screen, popup, lines)
end

return Suggest
