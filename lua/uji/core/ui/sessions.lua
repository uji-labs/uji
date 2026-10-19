local Approval = require("uji.core.ui.pickers.approval")
local class = require("uji.core.class")
local ito = require("ito")
local list = require("uji.utils.list")
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
    self.asking = nil
    self.scroll = ito.ScrollState()
end

function Sessions:move(delta)
    self:go(self.selection.value + delta)
end

function Sessions:go(index)
    self.selection.value = math.min(math.max(index, 1), math.max(#self.sessions, 1))
end

function Sessions:remove()
    local asking = self.asking
    self.asking = nil
    if not uji.session.delete(asking.id) then
        return
    end
    self.sessions = list.filtered(self.sessions, function(session)
        return session.id ~= asking.id
    end)
    self:go(self.selection.value)
end

function Sessions:key(incoming)
    local key = incoming.key
    if self.asking then
        if key == "y" or key == "Y" then
            self:remove()
        elseif key == "n" or key == "N" or key == "esc" then
            self.asking = nil
        end
        return
    end
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
    elseif (key == "D" or (key == "d" and incoming.shift)) and #self.sessions > 0 then
        self.asking = self.sessions[self.selection.value]
    elseif key == "esc" or (key == "q" and not incoming.ctrl and not incoming.alt) or (key == "c" and incoming.ctrl) then
        return false
    end
end

function Sessions:draw()
    self.window = self.window or ito.Window(ui:open(), function() end)
    local words = ui.theme:context().text
    local view = SessionList({
        directory = self.directory,
        sessions = self.sessions,
        selection = self.selection,
        now = sys.os.now(),
    })
    if self.asking then
        view = Approval({
            title = words.confirm_delete,
            body = string.format(words.confirm_delete_body, self.asking.title),
            allow = true,
            keys = { allow = "y", deny = "n" },
            allow_label = words.confirm_yes,
            deny_label = words.confirm_no,
            scroll = self.scroll,
        })
    end
    render.show(ui, self.window, view)
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
