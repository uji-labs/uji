local class = require("uji.core.class")
local ito = require("ito")
local markdown = require("uji.core.ui.markdown")
local sys = require("uji.sys")

local View = ito.View

local M = {}

local Transcript = class(View)
M.Transcript = Transcript

function Transcript:draw_content(frame)
    frame.pane = frame.pane or frame:transcript(self.inner)
end

local Activity = class(View)
M.Activity = Activity

function Activity:rows(frame, width)
    local activity = frame.ui:activity()
    return activity and frame.ctx:element("activity", activity, width) or {}
end

function Activity:content_height(frame, width)
    return #self:rows(frame, width)
end

function Activity:draw_content(frame)
    frame:lines(self.inner, self:rows(frame, self.inner.width))
end

local Markdown = class(View)
M.Markdown = Markdown

function Markdown:init(source)
    View.init(self, {})
    if type(source) ~= "string" then
        error("Markdown takes a string, not a " .. type(source), 3)
    end
    self.source = source
end

function Markdown:rendered(frame, width)
    if self.width_drawn ~= width then
        self.width_drawn = width
        self.drawn = markdown.render(frame.ctx, { events = markdown.parse(self.source), width = width })
    end
    return self.drawn
end

function Markdown:content_height(frame, width)
    return #self:rendered(frame, width)
end

function Markdown:draw_content(frame)
    frame:lines(self.inner, self:rendered(frame, self.inner.width))
end

local FULL = 100

M.Host = ito.Local(nil)

M.Hosted = ito.PreferenceKey({
    default = false,
    reduce = function(value, next_value)
        return value or next_value
    end,
})

local Input = class(View)

function Input:content_height(frame, width)
    return frame.ui.views.input:rows(frame.ui, width)
end

function Input:draw_content(frame)
    frame:lines(self.inner, frame.ui.views.input:view(frame.ui, frame.ctx, self.inner))
end

local Fill = class(View)

function Fill:content_height(frame, width)
    local child = self.composed[1]
    return child and child:measure(frame, width) or 0
end

function Fill:content_width(frame)
    local child = self.composed[1]
    return child and child:natural_width(frame)
end

local Sheet = class(Fill)

function Sheet:init(props)
    Fill.init(self, props)
    self.modal, self.clears, self.content = props.modal, props.clears, props.content
end

function Sheet:draw(frame)
    if not self.content.composed[1] then
        return
    end
    if self.clears then
        frame:clear(self.rect)
    end
    local outer = frame.scope
    frame.scope = self.modal
    Fill.draw(self, frame)
    frame.scope = outer
end

local Stacked = class(Fill)

function Stacked:init(props)
    Fill.init(self, props)
    self.hidden = props.hidden
end

function Stacked:compose(composition, node, environment)
    Fill.compose(self, composition, node, environment)
    local top = self.composed[#self.composed]
    self.composed = (top and not self.hidden) and { top } or {}
    return self
end

M.Presentation = ito.view(function(props)
    local ui, modal = M.Host.current, props.modal
    local view = modal:view(ui, ito.theme(), props.room)
    if not view then
        return nil
    end
    if not ito.is_view(view) then
        view = ito.Lines(view)
    end
    local content = Fill({ view })
    if props.fills then
        content:grow()
    end
    local placement = ito.ToolbarPlacement
    return Sheet({
        ito.ToolbarHost(ito.VStack({
            ito.HStack({
                ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
                ito.Spacer(),
                ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
            }),
            content,
            ito.ToolbarItems(placement.bottom_bar),
        })),
        modal = modal,
        clears = props.clears,
        content = content,
    })
end)

local function guarded(ui)
    return {
        failed = function(problem)
            ui:report("modal_failure", "modal: " .. sys.message(problem))
        end,
    }
end

M.Composer = ito.view(function()
    local ui = M.Host.current
    local takeovers = ui:takeovers()
    if #takeovers == 0 then
        return Input()
    end
    local layers = {}
    for index, modal in ipairs(takeovers) do
        layers[index] = ito.SubcomposeLayout(function(room)
            return M.Presentation({ modal = modal, room = room })
        end, guarded(ui)):id(modal)
    end
    return Stacked(layers)
end)

M.Modals = ito.view(function()
    local ui = M.Host.current
    local layers = {}
    for index, modal in ipairs(ui:inlines()) do
        layers[index] = ito.SubcomposeLayout(function(room)
            return ito.VStack({ ito.Spacer(), M.Presentation({ modal = modal, room = room, clears = true }) })
        end, guarded(ui)):id(modal)
    end
    return ito.VStack({ Stacked(layers) }):preference(M.Hosted, true)
end)

M.Floating = ito.view(function(props)
    local ui, limits = M.Host.current, ito.theme().limits
    local floats = ui:floats(props.hosted)
    local width = math.floor(ui.area.width * limits.float_width / FULL)
    local height = math.floor(ui.area.height * limits.float_height / FULL)
    local layers = {}
    for index, modal in ipairs(floats) do
        layers[index] = ito.SubcomposeLayout(function(room)
            return M.Presentation({ modal = modal, room = room, clears = true, fills = true })
        end, guarded(ui))
            :width(width)
            :height(height)
            :id(modal)
    end
    layers.hidden = floats[#floats] ~= ui.modal
    return ito.ZStack({ Stacked(layers) }):grow()
end)

M.slots = {
    transcript = function()
        return Transcript()
    end,
    composer = function()
        return M.Composer()
    end,
    modals = function()
        return M.Modals()
    end,
    activity = function()
        return Activity()
    end,
}

return M
