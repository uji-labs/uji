local app = require("uji.core.app")
local canvas = require("uji.core.ui.canvas")
local class = require("uji.core.class")
local layout = require("uji.core.ui.layout")
local Select = require("uji.core.ui.views.select")
local sys = require("uji.sys")
local text = require("uji.core.ui.text")
local ui = require("uji.core.ui")

local Picker = class(Select)

function Picker:init(store, directory, active)
    self.store, self.directory, self.active = store, directory, active
    Select.init(self, { title = "Sessions" })
    self:refresh()
end

function Picker:refresh()
    self.records, self.items = {}, {}
    for _, session in ipairs(self.store:sessions()) do
        if session.directory == self.directory then
            local title = (session.title == "" or session.title == "untitled") and "Untitled session" or session.title
            local label = title .. " · " .. session.id
            if session.id == self.active then
                label = label .. " (current)"
            end
            self.items[#self.items + 1] = label
            self.records[label] = session
        end
    end
    self:rerank()
end

function Picker:move(delta)
    self.problem = nil
    Select.move(self, delta)
end

function Picker:edited()
    self.problem = nil
    Select.edited(self)
end

function Picker:delete_prompt()
    local session = self.records[self:chosen()]
    if not session then
        return
    end
    if self.store:contains(session.id, self.active) then
        self.problem = "The open session cannot be deleted. Switch sessions first."
        return
    end
    self.deleting = session
    self.problem = nil
end

function Picker:confirm_delete()
    local session = self.deleting
    if not session then
        return
    end
    -- Recheck ownership immediately before deletion, not only when opening confirmation.
    if self.store:contains(session.id, self.active) then
        self.deleting = nil
        return
    end
    local ok, err = pcall(self.store.delete, self.store, session.id)
    self.deleting = nil
    if not ok then
        self.problem = tostring(err)
        return
    end
    self:refresh()
end

function Picker:line()
    return not self.deleting and self.query or nil
end

function Picker:rows()
    return Select.rows(self) + 1
end

function Picker:accept()
    if self.deleting then
        self.deleting = nil
        return
    end
    self:settle(self.records[self:chosen()])
end

function Picker:cancel()
    if self.deleting then
        self.deleting = nil
        return
    end
    self:settle(nil)
end

function Picker:key(chord, owner)
    if self.deleting then
        if chord.key == "y" and not chord.ctrl and not chord.alt and not chord.shift then
            self:confirm_delete()
        elseif chord.key == "esc" or chord.key == "enter" or chord.key == "n" then
            self.deleting = nil
        end
    elseif chord.key == "d" and chord.ctrl then
        self:delete_prompt()
    else
        Select.key(self, chord, owner)
    end
end

function Picker:draw(owner, screen, area)
    if self.deleting then
        local session = self.deleting
        local lines = {
            { { "Delete session and all child history?", owner.palette.accent } },
            { { text.clip(session.title, area.width), owner.palette.text } },
            { { text.clip(session.id, area.width), owner.palette.muted } },
            {},
            { { "y delete · Enter/Esc cancel", owner.palette.text } },
        }
        return canvas.popup(screen, area, lines, math.min(#lines, area.height))
    end
    if #self.items == 0 or self.problem then
        return canvas.popup(screen, area, {
            { { text.clip(self.problem or "No saved sessions · Esc cancel", area.width), owner.palette.muted } },
        }, 1)
    end
    Select.draw(self, owner, screen, layout.rect(area.x, area.y, area.width, math.max(area.height - 1, 0)))
    canvas.write(screen, area.y + area.height - 1, area.x, {
        { text.clip("  Enter resume · Ctrl-D delete · Esc close", area.width), owner.palette.muted },
    }, area.width)
end

local M = { Picker = Picker }

function M.pick(store)
    local picker = Picker(store, sys.os.cwd(), nil)
    local screen = ui:open()
    local previous = ui.modal
    ui.modal, picker.ui = picker, ui
    local function draw()
        local width, height = screen:size()
        ui.palette = ui.styles:sync(ui.theme)
        picker:draw(ui, screen, layout.rect(0, 0, width, height))
        screen:flush()
    end
    local ok, result = pcall(function()
        draw()
        for incoming in ui.input:events() do
            if incoming.type == "key" and (picker.deleting or (incoming.key == "d" and incoming.ctrl)) then
                picker:key(incoming, ui)
            else
                ui:handle(incoming)
            end
            if picker.answer.settled then
                return picker.answer:await()
            end
            draw()
        end
    end)
    ui.modal = previous
    if not ok then
        error(result, 0)
    end
    return result
end

function M.busy()
    return #ui.pending_sends > 0 or ui:working() or (app.agent and (app.agent.shell ~= nil or #app.agent.queue > 0))
end

function M.restart(session, fresh)
    assert(not M.busy(), "resolve pending work and queued messages before switching or reloading")
    local draft = ui.composer:text()
    assert(#ui.composer.pastes:images(draft) == 0, "submit or remove draft image attachments before switching or reloading")
    draft = ui.composer.pastes:expand(draft)
    local argv = { app.argv[1] or "uji", session and "resume" or "new" }
    if session then
        argv[#argv + 1] = "--id"
        argv[#argv + 1] = session.id
    end
    for _, flag in ipairs({ "config-dir", "data-dir", "db" }) do
        if app.flags[flag] then
            argv[#argv + 1] = "--" .. flag
            argv[#argv + 1] = app.flags[flag]
        end
    end
    local carry = { draft = draft }
    if not fresh and not session and app.session and app.session.pending then
        carry.session = { id = app.session.id, title = app.session.title }
    end
    sys.os.restart({ args = argv, roots = require("uji.core.packs").expected(), carry = sys.json.encode(carry) })
end

function M.switch(session)
    assert(not M.busy(), "resolve pending work and queued messages before switching sessions")
    if app.session and session.id == app.session.id then
        return
    end
    return M.restart(session)
end

return M
