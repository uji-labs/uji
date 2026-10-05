local class = require("uji.core.class")
local Modal = require("uji.core.ui.views.modal")

local Overlay = class(Modal)

Overlay.mode = "overlay"

function Overlay:init(content, opts)
    Modal.init(self)
    self.content = content
    self.float = not (opts and opts.float == false)
end

function Overlay:view()
    return self.content()
end

return Overlay
