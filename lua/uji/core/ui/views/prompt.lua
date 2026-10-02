local canvas = require("uji.core.ui.canvas")
local class = require("uji.core.class")
local Line = require("uji.core.ui.line")
local Modal = require("uji.core.ui.views.modal")

local ROWS = 4

local Prompt = class(Modal)

Prompt.mode = "prompt"

function Prompt:init(opts)
    Modal.init(self)
    self.title = opts.title or ""
    self.value = Line(opts.value or "")
    self.hidden = opts.hidden == true
end

function Prompt:line()
    return self.value
end

function Prompt:accept()
    self:settle(self.value.text)
end

function Prompt:rows()
    return ROWS
end

function Prompt:draw(ui, screen, area)
    if area.height <= 0 then
        return
    end
    local palette = ui.palette
    local typed = { { "  > ", palette.accent } }
    for _, span in ipairs(Modal.typed(self.value, self.hidden, palette.text, palette.muted)) do
        typed[#typed + 1] = span
    end
    local lines = { {}, { { "  " .. self.title, palette.bold } }, {}, typed }
    canvas.popup(screen, area, lines, math.min(ROWS, area.height))
end

return Prompt
