local actions = require("uji.core.ui.actions")
local app = require("uji.core.app")
local class = require("uji.core.class")
local command = require("uji.core.command")
local Composer = require("uji.core.ui.composer")
local Confirm = require("uji.core.ui.views.confirm")
local diagnostics = require("uji.core.diagnostics")
local event = require("uji.core.event")
local images = require("uji.core.images")
local ito = require("ito")
local keys = require("uji.core.ui.keys")
local Keymap = require("uji.core.ui.keymap")
local list = require("uji.utils.list")
local model = require("uji.core.model")
local notices = require("uji.core.notices")
local Pastes = require("uji.core.ui.paste")
local render = require("uji.core.ui.render")
local Stream = require("uji.core.ui.stream")
local Suggest = require("uji.core.ui.views.suggest")
local sys = require("uji.sys")
local task = require("uji.core.task")
local Theme = require("uji.core.ui.theme")

local FRAME = 1 / 60
local SCROLL_LINES = 3

local NORMAL = {
    backspace = "backspace",
    left = "cursor_left",
    right = "cursor_right",
    up = "history_prev",
    down = "history_next",
    pageup = "page_up",
    pagedown = "page_down",
    home = "scroll_top",
    ["end"] = "scroll_bottom",
    enter = "submit",
}

local function exit_text(exit)
    if exit.signal then
        return "signal: " .. exit.signal
    end
    return "exit status: " .. tostring(exit.code)
end

local Ui = class()

function Ui:init()
    self.toolbars = {}
    self.keymap = Keymap()
    self.theme = Theme()
    self.composer = Composer(self.theme)
    self.sends = task.sequence()
    self.stream = Stream()
    self.reasoning = ""
    self.notices = {}
    self.running = nil
    self.modal = nil
    self.presented = {}
    self.capture = nil
    self.scroll = ito.ScrollState({ follow = true })
    self.dirty = sys.promise()
    self.suspended = false
    ito.observable(self)
end

function Ui:open()
    if not self.screen then
        self.screen, self.input = ito.open()
        self.window = ito.Window(self.screen, function()
            self:invalidate()
        end)
    end
    return self.screen
end

function Ui:invalidate()
    if not self.dirty.settled then
        self.dirty:resolve()
    end
end

function Ui:toolbar(items)
    local declared = { items = items }
    for index, item in ipairs(items) do
        if item then
            item:id(declared, index)
        end
    end
    self.toolbars = list.appended(self.toolbars, declared)
    self:invalidate()
    return declared
end

function Ui:remove_toolbar(declared)
    for index, found in ipairs(self.toolbars) do
        if found == declared then
            self.toolbars = list.removed(self.toolbars, index)
            self:invalidate()
            return true
        end
    end
    return false
end

function Ui:present(modal)
    local top = self.modal
    if top and top.mode == "suggest" then
        top:close()
    end
    modal.ui = self
    self.presented = list.appended(self.presented, modal)
    self.modal = modal
    self:unfocus()
    self:invalidate()
    return modal
end

function Ui:ask(modal)
    return self:present(modal):wait()
end

function Ui:close_modal(modal)
    for index, found in ipairs(self.presented) do
        if found == modal then
            self.presented = list.removed(self.presented, index)
            self.modal = self.presented[#self.presented]
            self:unfocus()
            self:invalidate()
            return
        end
    end
end

function Ui:presentations(accept)
    local found = {}
    for _, modal in ipairs(self.presented) do
        if accept(modal) then
            found[#found + 1] = modal
        end
    end
    return found
end

function Ui:takeovers()
    return self:presentations(function(modal)
        return modal.takeover
    end)
end

function Ui:inlines()
    return self:presentations(function(modal)
        return not modal.takeover and not modal.float
    end)
end

function Ui:floats(hosted)
    return self:presentations(function(modal)
        return modal.float or (not hosted and not modal.takeover)
    end)
end

function Ui:mode()
    return self.modal and self.modal.mode or "normal"
end

function Ui:scroller()
    if self:mode() == "confirm" then
        return self.modal.scroll
    end
    return self.scroll
end

function Ui:working()
    return app.agent ~= nil and app.agent:working()
end

function Ui:loader_frame()
    local tokens = self.theme.tokens
    local frames = tokens.symbols.spinner
    local elapsed = app.agent and app.agent:elapsed()
    if not elapsed or #frames == 0 then
        return ""
    end
    local interval = math.max(tokens.limits.spinner_interval, 0.001)
    return frames[math.floor(elapsed / interval) % #frames + 1]
end

function Ui:current_activity()
    if not self:working() then
        return nil
    end
    return { elapsed = math.floor(app.agent:elapsed() or 0), frame = self:loader_frame() }
end

function Ui:interrupt()
    return app.agent ~= nil and app.agent:interrupt()
end

function Ui:quit()
    event.emit("before_quit", {})
    if self.screen then
        self.screen:close()
    end
    sys.os.exit(0)
end

function Ui:toggle_thinking()
    notices.push(self.theme:toggle_thinking() and "thinking: shown" or "thinking: hidden")
end

function Ui:suggestions()
    local query = self.composer:text():sub(2):lower()
    local items = {}
    for _, item in ipairs(command.suggestions()) do
        if item.name:lower():sub(1, #query) == query then
            items[#items + 1] = item
        end
    end
    return items
end

function Ui:composing()
    local mode = self:mode()
    return mode == "normal" or mode == "suggest"
end

function Ui:input_changed()
    local value = self.composer:text()
    local modal = self.modal
    if value:sub(1, 1) == "/" and not value:find(" ", 1, true) and self.theme.suggest_enabled then
        if self:mode() == "suggest" then
            modal:set(self:suggestions())
        elseif not modal then
            self:present(Suggest(self:suggestions()))
        end
    elseif self:mode() == "suggest" then
        modal:close()
    end
    self:invalidate()
end

function Ui:edit(change)
    local modal = self.modal
    local line = modal and modal:line()
    if line then
        local before = line.revision
        change(line)
        if line.revision ~= before then
            modal:edited()
        end
        return
    end
    if not self:composing() then
        return
    end
    local before = self.composer.line.revision
    self.composer:edit(change)
    if self.composer.line.revision ~= before then
        self:input_changed()
    end
end

function Ui:insert(value)
    self:edit(function(line)
        line:insert(value)
    end)
end

function Ui:backspace()
    if not self:composing() then
        self:edit(function(line)
            line:backspace()
        end)
        return
    end
    self.composer:backspace()
    self:input_changed()
end

function Ui:clear_input()
    self.composer:clear()
    self:input_changed()
end

function Ui:set_input(value)
    self.composer:set(value)
    self:input_changed()
end

local function sent(back)
    local entries = app.session and app.session:entries() or {}
    local seen = 0
    for index = #entries, 1, -1 do
        local message = entries[index].message
        if message.type == "user" then
            if seen == back then
                return message.text
            end
            seen = seen + 1
        end
    end
end

function Ui:history(direction)
    local composer = self.composer
    if direction < 0 then
        if composer:up() then
            return
        end
        composer:recall_prev(sent)
    else
        if composer:down() then
            return
        end
        composer:recall_next(sent)
    end
    self:input_changed()
end

function Ui:send(value, attached)
    local directory = app.directory()
    self.sends(function()
        for _, image in ipairs(images.mentioned(value, directory)) do
            attached[#attached + 1] = image
        end
        app.agent:submit(value, attached)
    end)
end

function Ui:attach(image)
    if model.images() == false then
        notices.push("the current model does not take images, so it gets the text only")
    end
    self.composer:attach(image)
    self:input_changed()
    self:invalidate()
end

function Ui:paste_image()
    task.spawn(function()
        local image, err = images.clipboard()
        if image then
            return self:attach(image)
        end
        local copied = sys.clipboard.get()
        if copied and copied ~= "" then
            return self:paste(copied)
        end
        notices.push(err)
    end)
end

function Ui:drop(value, files)
    task.spawn(function()
        local loaded = {}
        for index, file in ipairs(files) do
            local image = images.file(file, app.directory())
            if not image then
                self.composer:paste(value)
                self:input_changed()
                self:invalidate()
                return
            end
            loaded[index] = image
        end
        for _, image in ipairs(loaded) do
            self:attach(image)
        end
    end)
end

function Ui:run_command(line)
    task.spawn(function()
        command.run(line)
        self:invalidate()
    end)
end

function Ui:submit()
    local composer = self.composer
    if composer:continue_line() then
        self:input_changed()
        return
    end
    local taken, attached = composer:take()
    local value = ito.text.trim(taken)
    self:invalidate()
    if value:sub(1, 1) == "/" then
        return self:run_command(value:sub(2))
    end
    if value:sub(1, 1) == "!" then
        local shell = ito.text.trim(value:sub(2))
        if shell ~= "" then
            app.agent:run_shell(shell)
        end
        return
    end
    if value ~= "" then
        self:send(value, attached)
    end
end

function Ui:paste(value)
    local modal = self.modal
    local line = modal and modal:line()
    if line then
        line:insert(Pastes.single_line(value))
        modal:edited()
    elseif self:composing() then
        local files = images.paths(value)
        if files then
            return self:drop(value, files)
        end
        self.composer:paste(value)
        self:input_changed()
    end
    self:invalidate()
end

function Ui:act(name)
    local builtin = actions.RUN[name]
    if builtin then
        builtin(self)
        self:invalidate()
        return
    end
    local handler = actions.get(name)
    if not handler then
        notices.push("unknown keymap action: " .. name)
        return
    end
    task.spawn(function()
        local ok, err = pcall(handler)
        if not ok then
            notices.push("action " .. name .. ": " .. sys.message(err))
        end
        self:invalidate()
    end)
end

function Ui:captured(chord)
    local ok, err = pcall(self.capture, keys.capture(chord))
    if not ok then
        notices.push("capture handler: " .. sys.message(err))
        self.capture = nil
    end
end

function Ui:normal_key(chord)
    local key = chord.key
    if key == "esc" then
        if self.composer:text() == "" then
            self:interrupt()
        else
            self:clear_input()
        end
    elseif keys.is_char(chord) then
        if keys.typed(chord) then
            self:insert(key)
        end
    elseif NORMAL[key] then
        self:act(NORMAL[key])
    end
end

function Ui:unfocus()
    if self.window then
        self.window:unfocus()
    end
end

function Ui:key(chord)
    local window = self.window
    if window and window.selection:clear() then
        self:invalidate()
    end
    if self.capture then
        self:captured(chord)
    elseif window and window:key(chord) then
        self:invalidate()
    else
        local binding = self.keymap:get(self:mode(), chord)
        if binding and binding.command then
            self:run_command(binding.command)
        elseif binding and binding.action then
            self:act(binding.action)
        elseif not binding then
            if self.modal then
                self.modal:key(chord, self)
            else
                self:normal_key(chord)
            end
        end
    end
    self:invalidate()
end

function Ui:flash(message)
    local shown = { text = message }
    self.flashed = shown
    self:invalidate()
    task.spawn(function()
        sys.sleep(self.theme.tokens.limits.flash)
        if self.flashed == shown then
            self.flashed = nil
            self:invalidate()
        end
    end)
end

function Ui:copy(value)
    local count = #ito.text.lines(value)
    local words = self.theme.tokens.text
    if sys.clipboard.set(value) then
        self:flash(string.format(words.copied, count))
        return
    end
    self.screen:write("\27]52;c;" .. sys.base64.encode(value) .. "\7")
    self:flash(string.format(words.copied_terminal, count))
end

function Ui:mouse(incoming)
    local kind, window = incoming.kind, self.window
    if kind == "scroll_up" or kind == "scroll_down" then
        local rows = kind == "scroll_up" and -SCROLL_LINES or SCROLL_LINES
        if not window:wheel(incoming.row, incoming.col, rows) then
            self:scroller():scroll(rows)
        end
    elseif incoming.button == "left" and kind == "down" then
        window:press(incoming.row, incoming.col)
    elseif incoming.button == "left" and kind == "drag" then
        window:drag(incoming.row, incoming.col)
    elseif incoming.button == "left" and kind == "up" then
        local copied = window:release(incoming)
        if copied then
            self:copy(copied)
        end
    else
        return
    end
    self:invalidate()
end

function Ui:handle(incoming)
    local kind = incoming.type
    if kind == "key" then
        self:key(keys.from_event(incoming))
    elseif kind == "paste" then
        self:paste(incoming.text)
    elseif kind == "mouse" then
        self:mouse(incoming)
    elseif kind == "resize" then
        self:invalidate()
    end
end

function Ui:paint()
    self.window.scope = self.modal
    local frame = render.frame(self)
    if frame.wake and not self.waking then
        self.waking = true
        task.spawn(function()
            sys.sleep(frame.wake)
            self.waking = false
            self:invalidate()
        end)
    end
end

function Ui:render()
    self:paint()
    self.screen:flush()
end

function Ui:frames()
    while true do
        self.dirty:await()
        self.dirty = sys.promise()
        if not self.suspended then
            self.stream:reveal_step()
            local ok, failure = xpcall(self.render, diagnostics.capture, self)
            diagnostics.report("render", not ok and failure or nil)
            if self.stream:revealing() then
                self:invalidate()
            end
        end
        sys.sleep(FRAME)
    end
end

function Ui:read()
    for incoming in self.input:events() do
        self:handle(incoming)
    end
    self:quit()
end

function Ui:tick()
    if self.ticking or not self:working() then
        return
    end
    self.ticking = task.spawn(function()
        while self:working() do
            sys.sleep(self.theme.tokens.limits.spinner_interval)
            if self:working() then
                self.activity = self:current_activity()
                self:invalidate()
            end
        end
        self.ticking = nil
    end)
end

function Ui:exec(argv)
    task.spawn(function()
        local screen = self:open()
        self.suspended = true
        screen:suspend()
        local proc, err = sys.proc.spawn(argv, { stdio = "inherit" })
        local exit = proc and proc:wait()
        screen:resume()
        self.suspended = false
        if not proc then
            notices.push("run " .. argv[1] .. ": " .. tostring(err))
        elseif not exit.success then
            notices.push(argv[1] .. " exited with " .. exit_text(exit))
        end
        self:invalidate()
    end)
end

function Ui:progress(payload)
    if payload.name then
        self.running = { name = payload.name, line = payload.line or "" }
    elseif not payload.owner or (self.running and self.running.name == payload.owner) then
        self.running = nil
    end
    self:invalidate()
end

function Ui:delta(payload)
    if payload.kind == "reasoning" then
        self.reasoning = self.reasoning .. payload.text
    else
        self.stream:push(payload.text)
    end
    self:invalidate()
end

function Ui:clear_stream()
    self.stream:clear()
    self.reasoning = ""
    self:invalidate()
end

function Ui:take_notices()
    self.notices = list.extended(self.notices, notices.take())
    self:invalidate()
end

function Ui:confirm(request)
    local modal = Confirm(request)
    self:present(modal)
    app.agent.asking = modal
    local finished, answer = task.timeout(request.timeout, function()
        return modal:wait()
    end)
    app.agent.asking = nil
    if not finished then
        modal:close()
        return nil
    end
    return answer == true
end

function Ui:listen()
    local handlers = {
        notice = function()
            self:take_notices()
        end,
        message_submitted = function()
            self.notices = {}
            self.scroll:to_end()
            self:invalidate()
        end,
        stream_delta = function(payload)
            self:delta(payload)
        end,
        stream_cleared = function()
            self:clear_stream()
        end,
        tool_progress = function(payload)
            self:progress(payload)
        end,
        status_changed = function()
            self.activity = self:current_activity()
            self:tick()
            self:invalidate()
        end,
        scroll_to_bottom = function()
            self.scroll:to_end()
        end,
    }
    for _, name in ipairs({ "message_appended", "queue_changed", "session_titled", "model_changed", "session_compacted" }) do
        handlers[name] = function()
            self:invalidate()
        end
    end
    for name, handler in pairs(handlers) do
        event.on(name, handler, { name = "uji.ui." .. name })
    end
end

function Ui:start()
    self:open()
    self:listen()
    app.agent.confirm = function(request)
        return uji.ui.confirm(request)
    end
    self:take_notices()
    task.spawn(function()
        self:read()
    end)
    task.spawn(function()
        self:frames()
    end)
    self:invalidate()
end

return Ui()
