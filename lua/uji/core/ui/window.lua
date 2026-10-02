local class = require("uji.core.class")
local Theme = require("uji.core.ui.theme")
local Styles = require("uji.core.ui.styles")

local VIEWS = { messages = true, input = true, modal = true }
local SPLITS = { top = true, bottom = true, left = true, right = true }
local BORDERS = { none = true, plain = true, rounded = true, horizontal = true }

local DEFAULT_PRIORITY = 50

local function whole(value, what)
    if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 65535 then
        error(what .. " must fit in u16", 0)
    end
    return value
end

local function size(value)
    if type(value) == "number" then
        return whole(value, "size")
    end
    if value == "fill" or value == "auto" then
        return value
    end
    if type(value) == "string" then
        error("unknown size: " .. value .. ' (expected "fill" or "auto")', 0)
    end
    error('size must be a number or "fill"', 0)
end

local function extent(float, key)
    local value = float[key]
    if value == nil then
        return { percent = 80 }
    end
    if type(value) == "number" then
        if value % 1 ~= 0 or value < 0 or value > 65535 then
            error("float " .. key .. " must fit in a terminal", 0)
        end
        return { cells = value }
    end
    if type(value) == "string" then
        local percent = tonumber(value:match("^%s*(%d+)%s*%%%s*$"))
        if not percent or percent < 1 or percent > 100 then
            error("float " .. key .. ' must be "1%".."100%" or a cell count', 0)
        end
        return { percent = percent }
    end
    error("float " .. key .. " must be a percent string or a cell count", 0)
end

local function span(value)
    if type(value) == "string" then
        return { value }
    end
    local fill = type(value) == "table" and value.fill == true and value.text == nil
    if type(value) ~= "table" or (type(value.text) ~= "string" and not fill) then
        error("span must be a string or { text = .., color = .. }, got " .. tostring(value), 0)
    end
    local spec = {
        fg = value.color and Theme.color(value.color),
        bg = value.bg and Theme.color(value.bg),
        bold = value.bold == true or nil,
        italic = value.italic == true or nil,
        underline = value.underline == true or nil,
    }
    spec.key = Styles.key_of(spec)
    return { value.text or "", spec, fill = fill or nil }
end

local function line(value)
    if type(value) == "table" and value.text == nil then
        local spans = {}
        for index, item in ipairs(value) do
            spans[index] = span(item)
        end
        return spans
    end
    return { span(value) }
end

local Window = class()

Window.DEFAULT_PRIORITY = DEFAULT_PRIORITY
Window.size = size

function Window.lines(value)
    if type(value) ~= "table" then
        error("a renderer must return a list of lines", 0)
    end
    local lines = {}
    for index, item in ipairs(value) do
        lines[index] = line(item)
    end
    return lines
end

function Window:init(id, opts)
    opts = opts or {}
    if type(opts) ~= "table" then
        error("window options must be a table", 0)
    end
    if opts.view ~= nil and not VIEWS[opts.view] then
        error("unknown view: " .. tostring(opts.view) .. ' (expected "messages", "input" or "modal")', 0)
    end
    if opts.split ~= nil and not SPLITS[opts.split] then
        error("unknown split: " .. tostring(opts.split), 0)
    end
    if opts.border ~= nil and not BORDERS[opts.border] then
        error("unknown border: " .. tostring(opts.border), 0)
    end
    if opts.name ~= nil and type(opts.name) ~= "string" then
        error("name must be a string", 0)
    end
    self.id = id
    self.name = opts.name
    self.view = opts.view
    self.split = opts.split or "top"
    self.size = opts.size == nil and "fill" or size(opts.size)
    self.border = opts.border or "none"
    self.border_color = opts.border_color and Theme.color(opts.border_color)
    self.title = opts.title
    self.wrap = opts.wrap == true
    self.padding = opts.padding and whole(opts.padding, "padding") or 0
    self.priority = opts.priority or DEFAULT_PRIORITY
    if opts.float ~= nil then
        if type(opts.float) ~= "table" then
            error("float must be a table", 0)
        end
        self.float = { width = extent(opts.float, "width"), height = extent(opts.float, "height") }
    end
    self.lines = {}
    self.fitted = nil
end

function Window:effective_size()
    if self.size == "auto" then
        return self.fitted or 0
    end
    return self.size
end

function Window:chrome()
    local borders = self.border ~= "none" and 2 or 0
    return borders + self.padding * 2
end

function Window:boxed()
    return self.border == "plain" or self.border == "rounded"
end

return Window
