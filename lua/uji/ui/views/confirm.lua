local class = require("uji.class")
local keys = require("uji.ui.keys")
local Modal = require("uji.ui.views.modal")
local Scroll = require("uji.ui.scroll")
local text = require("uji.ui.text")

local ALLOW = { y = true, Y = true, ["1"] = true }
local DENY = { n = true, N = true, ["2"] = true }
local TOGGLE = { left = true, right = true, tab = true }
local SCROLLS = { pageup = "page_up", pagedown = "page_down", home = "scroll_top", ["end"] = "scroll_bottom" }

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
    local key = chord.key
    if key == "esc" or key == "enter" then
        Modal.key(self, chord, ui)
    elseif key == "up" then
        ui:act("modal_up")
    elseif key == "down" then
        ui:act("modal_down")
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

local function option(index, label, key, active, styles)
    local style = active and styles.selected or styles.unselected
    return {
        { active and "› " or "  ", style },
        { index .. ". " .. label, style },
        { " (" .. key .. ")", styles.dim },
    }
end

function Confirm:sections(ui, width)
    local palette = ui.palette
    local confirm = ui.theme.confirm
    local inner = math.max(width - 2, 1)
    local head = { {} }
    for _, chunk in ipairs(text.wrap(self.title, inner)) do
        head[#head + 1] = { { "  " .. chunk, palette.confirm_title } }
    end
    head[#head + 1] = {}
    local body = {}
    for _, chunk in ipairs(text.wrap(self.body, inner)) do
        body[#body + 1] = { { "  " .. chunk, palette.confirm_body } }
    end
    local styles = {
        selected = palette.confirm_selected,
        unselected = palette.confirm_unselected,
        dim = palette.dim,
    }
    local foot = {
        {},
        option(1, confirm.yes .. ", proceed", "y", self.allow, styles),
        option(2, confirm.no .. ", and tell uji what to do differently", "esc", not self.allow, styles),
        {},
    }
    return head, body, foot
end

function Confirm:takeover_rows(ui, width)
    local head, body, foot = self:sections(ui, width)
    return #head + #body + #foot
end

function Confirm:lines(ui, width, height)
    local head, body, foot = self:sections(ui, width)
    local room = math.max(height - #head - #foot, 1)
    local hidden = math.max(#body - room, 0)
    local shown = body
    if hidden > 0 then
        local offset = self.scroll:resolve(hidden, room)
        foot[1] = {
            {
                string.format("  lines %d-%d of %d, scroll for more", offset + 1, offset + room, #body),
                ui.palette.dim,
            },
        }
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
