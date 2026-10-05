local class = require("uji.core.class")
local Line = require("ito").Line
local Modal = require("uji.core.ui.views.modal")
local model = require("uji.core.model")
local sys = require("uji.sys")

local PAGE = 10

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
    if Modal.navigate(chord, ui) then
        return
    end
    local key = chord.key
    if key == "pageup" then
        self:move(-PAGE)
    elseif key == "pagedown" then
        self:move(PAGE)
    else
        Modal.key(self, chord, ui)
    end
end

function Select:data(height)
    return {
        title = self.title,
        query = self.query,
        items = self.items,
        matches = self.matches,
        selection = self:selection(),
        current = model.current.model or "",
        height = height,
    }
end

function Select:view(_, ctx, area)
    if #self.items == 0 then
        return nil
    end
    return ctx:element("select", self:data(area.height), area.width)
end

return Select
