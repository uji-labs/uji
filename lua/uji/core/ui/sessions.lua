local class = require("uji.core.class")
local render = require("uji.core.ui.render")
local sys = require("uji.sys")
local ui = require("uji.core.ui")

local PAGE = 10

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

function Sessions:draw()
    render.show(ui, "sessions", {
        directory = self.directory,
        sessions = self.sessions,
        cursor = self.cursor,
        now = sys.os.now(),
    })
end

local M = { Sessions = Sessions }

function M.pick(sessions)
    local screen = ui:open()
    local picker = Sessions(sessions, sys.os.cwd())
    picker:draw()
    screen:flush()
    for incoming in ui.input:events() do
        if incoming.type == "key" then
            local chosen = picker:key(incoming)
            if chosen ~= nil then
                return chosen or nil
            end
        end
        picker:draw()
        screen:flush()
    end
end

return M
