local Approval = require("uji.core.ui.pickers.approval")
local class = require("uji.core.class")
local ito = require("ito")
local keys = require("uji.core.ui.keys")
local Modal = require("uji.core.ui.views.modal")

local ALLOW = { y = true, Y = true, ["1"] = true }
local DENY = { n = true, N = true, ["2"] = true }
local TOGGLE = { left = true, right = true, tab = true }
local SCROLLS = { pageup = "page_up", pagedown = "page_down", home = "scroll_top", ["end"] = "scroll_bottom" }
local KEYS = { allow = "y", deny = "esc" }

local Confirm = class(Modal)

Confirm.mode = "confirm"
Confirm.takeover = true

function Confirm:init(opts)
    Modal.init(self)
    self.title = opts.title or ""
    self.body = opts.body or ""
    self.preview = opts.preview
    self.allow = true
    self.scroll = ito.ScrollState()
end

function Confirm:accept()
    self:settle(self.allow)
end

function Confirm:cancel()
    self:settle(false)
end

function Confirm:toggle()
    self.allow = not self.allow
end

function Confirm:move(delta)
    self.allow = delta < 0
end

function Confirm:key(chord, ui)
    if Modal.navigate(chord, ui) then
        return
    end
    local key = chord.key
    if key == "esc" or key == "enter" then
        Modal.key(self, chord, ui)
    elseif keys.typed(chord) and ALLOW[key] then
        ui:act("confirm_allow")
    elseif keys.typed(chord) and DENY[key] then
        ui:act("confirm_deny")
    elseif TOGGLE[key] then
        ui:act("confirm_toggle")
    elseif SCROLLS[key] then
        ui:act(SCROLLS[key])
    end
end

function Confirm:view()
    return Approval({
        title = self.title,
        body = self.body,
        preview = self.preview,
        allow = self.allow,
        keys = KEYS,
        scroll = self.scroll,
    })
end

return Confirm
