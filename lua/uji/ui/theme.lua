local class = require("uji.class")

local COLORS = {
    black = true,
    red = true,
    green = true,
    yellow = true,
    blue = true,
    magenta = true,
    cyan = true,
    white = true,
    gray = true,
    grey = true,
    dark_gray = true,
    dark_grey = true,
    light_red = true,
    light_green = true,
    light_yellow = true,
    light_blue = true,
    light_magenta = true,
    light_cyan = true,
}

local PALETTE = {
    text = "#d4d4d4",
    muted = "#808080",
    code = "#e0af68",
    accent = "cyan",
    user_bg = "#343541",
    selected_bg = "#3a3a4a",
    cursor = "white",
    error = "red",
    notice = "red",
}

local SCHEMA = {
    show_thinking = "boolean",
    theme = {
        text = "color",
        muted = "color",
        code = "color",
        accent = "color",
        user_bg = "color",
        selected_bg = "color",
        cursor = "color",
        error = "color",
        notice = "color",
        input = "color",
        confirm_title = "color",
        confirm_body = "color",
        confirm_selected = "color",
        confirm_unselected = "color",
    },
    input = { cursor_blink = "boolean" },
    suggest = { enabled = "boolean", max_height = "count" },
    waiting = { loader = { frames = "strings", interval = "seconds" } },
    confirm = { title = "string", yes = "string", no = "string" },
}

local function color(value)
    if type(value) ~= "string" then
        error("a colour must be a string, not a " .. type(value), 0)
    end
    if value:sub(1, 1) == "#" then
        if not value:match("^#%x%x%x%x%x%x$") then
            error("invalid color: " .. value .. " (expected #rrggbb)", 0)
        end
        return value
    end
    if not COLORS[value] then
        error("unknown color: " .. value, 0)
    end
    return value
end

local CHECKS = {
    boolean = function(value, path)
        if type(value) ~= "boolean" then
            error(path .. " must be true or false", 0)
        end
    end,
    string = function(value, path)
        if type(value) ~= "string" then
            error(path .. " must be a string", 0)
        end
    end,
    count = function(value, path)
        if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then
            error(path .. " must be a whole number", 0)
        end
    end,
    seconds = function(value, path)
        if type(value) ~= "number" or value <= 0 then
            error(path .. " must be a positive number of seconds, not " .. tostring(value), 0)
        end
    end,
    strings = function(value, path)
        if type(value) ~= "table" then
            error(path .. " must be a list of strings", 0)
        end
        for _, item in ipairs(value) do
            if type(item) ~= "string" then
                error(path .. " must be a list of strings", 0)
            end
        end
    end,
    color = function(value)
        color(value)
    end,
}

local function check(value, schema, path)
    if type(value) ~= "table" then
        error((path == "" and "options" or path) .. " must be a table", 0)
    end
    for key, item in pairs(value) do
        local rule = schema[key]
        local at = path == "" and tostring(key) or path .. "." .. tostring(key)
        if rule == nil then
            error("unknown option: " .. at, 0)
        end
        if type(rule) == "table" then
            check(item, rule, at)
        else
            CHECKS[rule](item, at)
        end
    end
end

local revisions = 0

local function revise()
    revisions = revisions + 1
    return revisions
end

local Theme = class()

Theme.color = color

function Theme:init()
    self.palette = {}
    for key, value in pairs(PALETTE) do
        self.palette[key] = value
    end
    self.input = nil
    self.confirm = { title = "Allow tool call?", yes = "Yes", no = "No" }
    self.show_thinking = false
    self.cursor_blink = true
    self.suggest_enabled = true
    self.suggest_max_height = 5
    self.loader_frames = {}
    self.loader_interval = 0.08
    self.revision = revise()
end

function Theme:configure(opts)
    check(opts, SCHEMA, "")
    local theme = opts.theme or {}
    for key in pairs(PALETTE) do
        if theme[key] then
            self.palette[key] = theme[key]
        end
    end
    self.input = theme.input or self.input
    local confirm = self.confirm
    confirm.title_color = theme.confirm_title or confirm.title_color
    confirm.body_color = theme.confirm_body or confirm.body_color
    confirm.selected = theme.confirm_selected or confirm.selected
    confirm.unselected = theme.confirm_unselected or confirm.unselected
    if opts.confirm then
        confirm.title = opts.confirm.title or confirm.title
        confirm.yes = opts.confirm.yes or confirm.yes
        confirm.no = opts.confirm.no or confirm.no
    end
    if opts.show_thinking ~= nil then
        self.show_thinking = opts.show_thinking
    end
    if opts.input and opts.input.cursor_blink ~= nil then
        self.cursor_blink = opts.input.cursor_blink
    end
    if opts.suggest then
        if opts.suggest.enabled ~= nil then
            self.suggest_enabled = opts.suggest.enabled
        end
        self.suggest_max_height = opts.suggest.max_height or self.suggest_max_height
    end
    local loader = opts.waiting and opts.waiting.loader
    if loader then
        if loader.frames then
            self.loader_frames = { unpack(loader.frames) }
        end
        self.loader_interval = loader.interval or self.loader_interval
    end
    self.revision = revise()
end

function Theme:toggle_thinking()
    self.show_thinking = not self.show_thinking
    self.revision = revise()
    return self.show_thinking
end

return Theme
