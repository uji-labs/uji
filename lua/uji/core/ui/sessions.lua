local class = require("uji.core.class")
local ito = require("ito")
local render = require("uji.core.ui.render")
local SessionList = require("uji.core.ui.pickers.sessions")
local sys = require("uji.sys")
local ui = require("uji.core.ui")

local PAGE = 10

local Sessions = class()

function Sessions:init(sessions, directory)
    self.sessions = sessions
    self.directory = directory
    self.selection = { value = 1 }
end

function Sessions:move(delta)
    self:go(self.selection.value + delta)
end

function Sessions:go(index)
    self.selection.value = math.min(math.max(index, 1), math.max(#self.sessions, 1))
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
        self:go(1)
    elseif key == "end" then
        self:go(#self.sessions)
    elseif key == "enter" and #self.sessions > 0 then
        return self.sessions[self.selection.value]
    elseif key == "esc" or (key == "q" and not incoming.ctrl and not incoming.alt) or (key == "c" and incoming.ctrl) then
        return false
    end
end

function Sessions:draw()
    self.window = self.window or ito.Window(ui:open(), function() end)
    render.show(
        ui,
        self.window,
        SessionList({
            directory = self.directory,
            sessions = self.sessions,
            selection = self.selection,
            now = sys.os.now(),
        })
    )
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
