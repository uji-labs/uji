local canvas = require("uji.ui.canvas")
local class = require("uji.class")
local layout = require("uji.ui.layout")
local sys = require("uji.sys")
local text = require("uji.ui.text")
local ui = require("uji.ui")

local UPDATED_WIDTH = 14
local ID_WIDTH = 36
local GAP = "  "
local PAGE = 10

local UNITS = {
    { 60, 1, "second" },
    { 3600, 60, "minute" },
    { 86400, 3600, "hour" },
    { 604800, 86400, "day" },
    { 2592000, 604800, "week" },
    { 31536000, 2592000, "month" },
    { math.huge, 31536000, "year" },
}

local function ago(millis)
    local seconds = math.max(math.floor((sys.os.now() - (millis or 0)) / 1000), 0)
    if seconds < 10 then
        return "now"
    end
    for _, unit in ipairs(UNITS) do
        if seconds < unit[1] then
            local count = math.floor(seconds / unit[2])
            if count <= 1 then
                return (unit[3] == "hour" and "an " or "a ") .. unit[3] .. " ago"
            end
            return count .. " " .. unit[3] .. "s ago"
        end
    end
end

local function cell(value, width)
    return text.pad(text.clip(value, width), width)
end

local Sessions = class()

function Sessions:init(sessions, directory)
    self.sessions = sessions
    self.directory = directory
    self.cursor = 1
end

function Sessions:move(delta)
    self.cursor = math.min(math.max(self.cursor + delta, 1), math.max(#self.sessions, 1))
end

function Sessions:key(incoming)
    local key = incoming.key
    if key == "up" then
        self:move(-1)
    elseif key == "down" then
        self:move(1)
    elseif key == "pageup" then
        self:move(-PAGE)
    elseif key == "pagedown" then
        self:move(PAGE)
    elseif key == "home" then
        self.cursor = 1
    elseif key == "end" then
        self.cursor = math.max(#self.sessions, 1)
    elseif key == "enter" and #self.sessions > 0 then
        return self.sessions[self.cursor]
    elseif key == "esc" or (key == "q" and not incoming.ctrl and not incoming.alt) or (key == "c" and incoming.ctrl) then
        return false
    end
end

function Sessions:row(palette, values, width, style)
    local title = math.max(width - UPDATED_WIDTH - ID_WIDTH - #GAP * 2, 0)
    local line = cell(values[1], title) .. GAP .. cell(values[2], UPDATED_WIDTH) .. GAP .. cell(values[3], ID_WIDTH)
    return { { text.clip(line, width), style or palette.text } }
end

function Sessions:draw(screen, palette)
    local width, height = screen:size()
    local list = layout.rect(0, 0, width, height - 1)
    local inner = canvas.block(screen, list, {
        border = "plain",
        style = palette.highlight,
        title = " Sessions in " .. self.directory .. " ",
    })
    local lines = { self:row(palette, { "TITLE", "UPDATED", "ID" }, inner.width, ui.styles:with(palette.muted, { bold = true })) }
    if #self.sessions == 0 then
        lines[2] = { { "No sessions in current directory", palette.muted } }
    else
        local available = math.max(inner.height - 1, 1)
        local start = 0
        if self.cursor > available then
            start = math.min(self.cursor - available, #self.sessions - available)
        end
        for at = start + 1, math.min(start + available, #self.sessions) do
            local session = self.sessions[at]
            local style = at == self.cursor and palette.chosen or palette.text
            local line = self:row(palette, { session.title, ago(session.updated), session.id }, inner.width, style)
            if at == self.cursor then
                local used = text.width(line[1][1])
                line[2] = { string.rep(" ", math.max(inner.width - used, 0)), palette.selected }
            end
            lines[#lines + 1] = line
        end
    end
    canvas.lines(screen, inner, lines)
    local hint
    if #self.sessions == 0 then
        hint = { { "esc", palette.highlight }, { " quit", palette.muted } }
    else
        hint = {
            { "↑/↓", palette.highlight },
            { " navigate   ", palette.muted },
            { "enter", palette.highlight },
            { " resume   ", palette.muted },
            { "esc", palette.highlight },
            { " quit", palette.muted },
        }
    end
    canvas.write(screen, height - 1, 0, hint, width)
    screen:flush()
end

local M = {}

function M.pick(store)
    local directory = sys.os.cwd()
    local sessions = {}
    for _, session in ipairs(store:sessions()) do
        if session.directory == directory then
            sessions[#sessions + 1] = session
        end
    end
    local screen = ui:open()
    local palette = ui.styles:sync(ui.theme)
    local picker = Sessions(sessions, directory)
    picker:draw(screen, palette)
    for incoming in ui.input:events() do
        if incoming.type == "key" then
            local chosen = picker:key(incoming)
            if chosen ~= nil then
                return chosen or nil
            end
        end
        picker:draw(screen, palette)
    end
end

return M
