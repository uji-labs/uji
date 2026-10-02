local app = require("uji.core.app")
local canvas = require("uji.core.ui.canvas")
local class = require("uji.core.class")
local layout = require("uji.core.ui.layout")
local notices = require("uji.core.notices")
local Modal = require("uji.core.ui.views.modal")
local Select = require("uji.core.ui.views.select")
local sys = require("uji.sys")
local tool = require("uji.core.tool")

local PROMPT_ROWS = 3
local MIN_PREVIEW = 24
local CONTEXT_LINES = 40
local DEBOUNCE = 0.12

local function location(item)
    local path, rest = item:match("^([^:]+):(.*)$")
    if not path then
        return nil
    end
    local line = tonumber((rest:match("^([^:]*)") or rest):match("^%s*(%d+)%s*$"))
    return line and path, line
end

local Pick = class(Select)

Pick.float = true

function Pick:init(opts)
    Select.init(self, opts)
    self.on_preview = opts.preview
    self.on_query = opts.on_query
    self.preview = {}
    self.previewed = nil
    self.generation = 0
    if self.on_query then
        self:query_later()
    end
end

function Pick:rows()
    return nil
end

function Pick:edited()
    Select.edited(self)
    if self.on_query then
        self:query_later()
    end
end

function Pick:query_later()
    if self.waiting then
        self.waiting:cancel()
    end
    local query = self.query.text
    if query == self.sent then
        self.waiting = nil
        return
    end
    self.waiting = sys.task.spawn(function()
        sys.sleep(DEBOUNCE)
        self.waiting = nil
        self.sent = query
        self.generation = self.generation + 1
        local generation = self.generation
        local ok, err = pcall(self.on_query, query, function(items)
            if generation == self.generation and not self.answer.settled then
                self:show(items)
            end
        end)
        if not ok then
            notices.push("pick query: " .. sys.message(err))
        end
    end)
end

function Pick:show(items)
    self.items = {}
    for index, item in ipairs(items or {}) do
        self.items[index] = tostring(item)
    end
    self.matches = {}
    for index = 1, #self.items do
        self.matches[index] = index
    end
    self.cursor = 1
    self.previewed = nil
    if self.ui then
        self.ui:invalidate()
    end
end

function Pick:fetch(item)
    if self.on_preview then
        local ok, lines = pcall(self.on_preview, item)
        if not ok then
            notices.push("preview: " .. tostring(lines))
            return {}
        end
        return type(lines) == "table" and lines or {}
    end
    local path, line = location(item)
    if not path then
        return {}
    end
    local lines, err = tool.files(app.directory()):around(path, line, CONTEXT_LINES)
    return lines or { tostring(err) }
end

function Pick:refresh(ui)
    local item = self:chosen()
    if not item or item == self.previewed then
        return
    end
    self.previewed = item
    if self.loading then
        self.loading:cancel()
    end
    self.loading = sys.task.spawn(function()
        local lines = self:fetch(item)
        self.loading = nil
        self.preview = lines
        ui:invalidate()
    end)
end

function Pick:settle(value)
    if self.waiting then
        self.waiting:cancel()
        self.waiting = nil
    end
    if self.loading then
        self.loading:cancel()
        self.loading = nil
    end
    Modal.settle(self, value)
end

function Pick:results(ui, screen, area)
    local palette = ui.palette
    local inner = canvas.block(screen, area, {
        border = "plain",
        style = palette.border,
        title = { { " " .. self.title .. " ", palette.accent } },
    })
    local rows = inner.height
    local start = math.max(self.cursor - rows, 0)
    local lines = {}
    for at = start + 1, math.min(start + rows, #self.matches) do
        local item = self.items[self.matches[at]]
        if at == self.cursor then
            lines[#lines + 1] = { { "> " .. item, palette.chosen } }
        else
            lines[#lines + 1] = { { "  " .. item, palette.text } }
        end
    end
    canvas.lines(screen, inner, lines)
end

function Pick:previewing(ui, screen, area)
    if area.width <= 0 then
        return
    end
    local palette = ui.palette
    local inner = canvas.block(screen, area, { border = "plain", style = palette.border })
    local lines = {}
    for index = 1, math.min(#self.preview, inner.height) do
        lines[index] = { { tostring(self.preview[index]), palette.muted } }
    end
    canvas.lines(screen, inner, lines)
end

function Pick:prompt(ui, screen, area)
    local palette = ui.palette
    local inner = canvas.block(screen, area, { border = "plain", style = palette.border })
    local line = { { "> ", palette.accent } }
    for _, span in ipairs(Modal.typed(self.query, false, palette.text, palette.muted)) do
        line[#line + 1] = span
    end
    line[#line + 1] = { string.format("   %d/%d", #self.matches, #self.items), palette.dim }
    canvas.lines(screen, inner, { line })
end

function Pick:draw(ui, screen, area)
    self:refresh(ui)
    if area.height < PROMPT_ROWS + 3 or area.width < 20 then
        return
    end
    canvas.clear(screen, area)
    local body = layout.rect(area.x, area.y, area.width, area.height - PROMPT_ROWS)
    local split = body.width < MIN_PREVIEW * 2 and body.width or math.floor(body.width / 2)
    self:results(ui, screen, layout.rect(body.x, body.y, split, body.height))
    self:previewing(ui, screen, layout.rect(body.x + split, body.y, body.width - split, body.height))
    self:prompt(ui, screen, layout.rect(area.x, body.y + body.height, area.width, PROMPT_ROWS))
end

return Pick
