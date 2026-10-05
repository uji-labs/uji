local class = require("uji.core.class")
local ito = require("ito")
local Modal = require("uji.core.ui.views.modal")

local Overlay = class(Modal)

Overlay.mode = "overlay"

function Overlay:init(content, opts)
    Modal.init(self)
    self.body = ito.body(content)
    self.float = not (opts and opts.float == false)
end

function Overlay:view()
    return self.body()
end

return Overlay
