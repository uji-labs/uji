local canvas = require("uji.ui.canvas")
local class = require("uji.class")
local layout = require("uji.ui.layout")
local Line = require("uji.ui.line")
local Modal = require("uji.ui.views.modal")
local model = require("uji.model")
local sys = require("uji.sys")
local text = require("uji.ui.text")

local MAX_ROWS = 12
local PAGE = 10

local function visible_start(cursor, count, available)
    if count <= available then
        return 0
    end
    return math.min(math.max(cursor - math.floor(available / 2), 0), count - available)
end

local Select = class(Modal)

Select.mode = "select"

function Select:init(opts)
    Modal.init(self)
    self.title = opts.title or ""
    self.items = {}
    for index, item in ipairs(opts.items or {}) do
        self.items[index] = tostring(item)
    end
    self.query = Line()
    self:rerank()
end

function Select:line()
    return self.query
end

function Select:rerank()
    self.cursor = 1
    self.matches = sys.fuzzy(self.query.text, self.items)
end

function Select:edited()
    self:rerank()
end

function Select:move(delta)
    self.cursor = Modal.step(self.cursor, delta, #self.matches)
end

function Select:chosen()
    local index = self.matches[self.cursor]
    return index and self.items[index]
end

function Select:accept()
    self:settle(self:chosen())
end

function Select:key(chord, ui)
    local key = chord.key
    if key == "up" then
        ui:act("modal_up")
    elseif key == "down" then
        ui:act("modal_down")
    elseif key == "pageup" then
        self:move(-PAGE)
    elseif key == "pagedown" then
        self:move(PAGE)
    else
        Modal.key(self, chord, ui)
    end
end

function Select:rows()
    local visible = math.min(#self.matches, MAX_ROWS)
    return visible + 4 + (#self.matches > visible and 1 or 0)
end

function Select:query_line(palette)
    local line = { { "  > ", palette.accent } }
    for _, span in ipairs(Modal.typed(self.query, false, palette.text, palette.muted)) do
        line[#line + 1] = span
    end
    return line
end

function Select:draw(ui, screen, area)
    if #self.items == 0 or area.height < 4 then
        return
    end
    local palette = ui.palette
    local current = model.current.model or ""
    local count = #self.matches
    local visible = math.min(count, MAX_ROWS, area.height - 4)
    local start = visible_start(self.cursor - 1, count, visible)
    local lines = { {}, { { "  " .. self.title, palette.bold } }, {}, self:query_line(palette) }
    for offset = 1, visible do
        local at = start + offset
        local item = self.items[self.matches[at]]
        local active = at == self.cursor
        local line = { { text.clip((active and "› " or "  ") .. item, area.width), active and palette.accent or palette.text } }
        if item == current then
            line[#line + 1] = { " (current)", palette.muted }
        end
        lines[#lines + 1] = line
    end
    if count > visible then
        lines[#lines + 1] = { { string.format("  %d–%d of %d", start + 1, start + visible, count), palette.dim } }
    end
    local height = math.min(#lines, area.height)
    local popup = layout.rect(area.x, area.y + area.height - height, area.width, height)
    canvas.clear(screen, popup)
    canvas.lines(screen, popup, lines)
end

return Select
