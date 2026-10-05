local class = require("uji.core.class")
local ito = require("ito")
local parts = require("uji.core.ui.parts")
local sys = require("uji.sys")

local M = {}

local function width_of(line)
    local total = 0
    for _, span in ipairs(line) do
        total = total + ito.text.width(span[1])
    end
    return total
end

local Frame = class(ito.Frame)

function Frame:init(ui, screen)
    ito.Frame.init(self, screen, ui.theme:context())
    ito.Theme:set(self.ctx)
    self.ui = ui
end

function Frame:compose(composition, element)
    return composition:compose(ito.Theme:provide(self.ctx, element))
end

function Frame:focusable(target, handle, wanted)
    ito.Frame.focusable(self, target, handle, wanted)
    self.focusables[#self.focusables].scope = self.scope
end

local Root = ito.view(function(props)
    local view = props.template(ito.theme(), parts.slots)
    if not view then
        error("a screen template must give a view", 0)
    end
    local host = ito.ToolbarHost(view)
    for _, declared in ipairs(props.ui.toolbars) do
        host:toolbar(declared.items)
    end
    return host:overlay_preference_value(parts.Hosted, function(hosted)
        return parts.Floating({ hosted = hosted })
    end)
end)

function Frame:build(template, area)
    local ui = self.ui
    local root = self:compose(ui.composition, parts.Host:provide(ui, Root({ ui = ui, template = template })))
    root:place(self, area)
    return root
end

function Frame:tree(area)
    local ui, ctx = self.ui, self.ctx
    ctx.width, ctx.height = area.width, area.height
    ui.composition = ui.composition or ito.Composition(function()
        ui:invalidate()
    end)
    local ok, root = pcall(self.build, self, ctx.templates.screen, area)
    if ok then
        ui.screen_failure = nil
        return root
    end
    ui:report("screen_failure", "screen: " .. sys.message(root))
    return self:build(ui.theme.default.templates.screen, area)
end

function Frame:transcript(rect)
    local drawn = self.ui.views.messages:draw(self.ui, rect, self.ctx)
    self:lines(drawn.area, drawn.rows)
    local jump = drawn.jump
    if jump then
        self.screen:line(jump.row, jump.col, jump.line, jump.width)
    end
    return drawn.pane
end

function Frame:highlight()
    local ui = self.ui
    for _, rect in ipairs(ui.selection:sync(self.screen, not ui.modal and self.pane or nil)) do
        self.screen:paint(rect, self.ctx.styles.selection)
    end
end

function Frame:flash(area)
    local flashed = self.ui.flashed
    if not flashed then
        return
    end
    local line = self.ctx:element("flash", { text = flashed.text }, area.width)[1] or {}
    local size = math.min(width_of(line), area.width)
    self.screen:line(0, area.width - size, line, size)
end

function M.frame(ui, screen, area)
    local frame = Frame(ui, screen)
    local root = frame:tree(area)
    root:draw(frame)
    frame:highlight()
    frame:flash(area)
    return frame
end

function M.show(ui, name, data)
    local screen = ui:open()
    local width, height = screen:size()
    local frame = Frame(ui, screen)
    data.height = height
    local root = frame:compose(ito.Composition(), frame.ctx:element(name, data, width))
    local area = ito.layout.rect(0, 0, width, height)
    screen:clear()
    root:place(frame, area)
    root:draw(frame)
end

return M
