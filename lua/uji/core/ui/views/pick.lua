local app = require("uji.core.app")
local class = require("uji.core.class")
local Files = require("uji.core.system.files")
local notices = require("uji.core.notices")
local Modal = require("uji.core.ui.views.modal")
local Picker = require("uji.core.ui.pickers.picker")
local Select = require("uji.core.ui.views.select")
local sys = require("uji.sys")

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
    self:fill(items)
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
    local path, line = location(self.label(item))
    if not path then
        return {}
    end
    local lines, err = Files(app.directory()):around(path, line, CONTEXT_LINES)
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

function Pick:view(ui)
    self:refresh(ui)
    return Picker({
        title = self.title,
        items = self.items,
        matches = self.matches,
        selection = self:selection(),
        current = self.current,
        preview = self.preview,
        query = self.query,
        total = #self.items,
    })
end

return Pick
