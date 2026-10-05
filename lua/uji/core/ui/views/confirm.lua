local class = require("uji.core.class")
local keys = require("uji.core.ui.keys")
local Modal = require("uji.core.ui.views.modal")
local Scroll = require("uji.core.ui.scroll")

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
    self.allow = true
    self.scroll = Scroll()
    self.scroll:top()
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

function Confirm:sections(ctx, width, scroll)
    local data = { title = self.title, body = self.body, allow = self.allow, keys = KEYS, scroll = scroll }
    return ctx:element("confirm", data, width)
end

function Confirm:view(_, ctx, area)
    local sections = self:sections(ctx, area.width)
    local head, body, foot = sections.head, sections.body, sections.foot
    local room = math.max(area.height - #head - #foot, 1)
    local hidden = math.max(#body - room, 0)
    local shown = body
    if hidden > 0 then
        local offset = self.scroll:resolve(hidden, room)
        foot = self:sections(ctx, area.width, { first = offset + 1, last = offset + room, total = #body }).foot
        shown = {}
        for index = offset + 1, math.min(offset + room, #body) do
            shown[#shown + 1] = body[index]
        end
    end
    local out = {}
    for _, part in ipairs({ head, shown, foot }) do
        for _, line in ipairs(part) do
            out[#out + 1] = line
        end
    end
    return out
end

return Confirm
