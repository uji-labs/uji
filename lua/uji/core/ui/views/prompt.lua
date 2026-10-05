local class = require("uji.core.class")
local Line = require("ito").Line
local Modal = require("uji.core.ui.views.modal")
local PromptField = require("uji.core.ui.pickers.prompt_field")

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

function Prompt:view()
    return PromptField({
        title = self.title,
        value = { text = self.value.text, cursor = self.value.cursor, hidden = self.hidden },
    })
end

return Prompt
