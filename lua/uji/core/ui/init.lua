local actions = require("uji.core.ui.actions")
local app = require("uji.core.app")
local canvas = require("uji.core.ui.canvas")
local class = require("uji.core.class")
local command = require("uji.core.command")
local Composer = require("uji.core.ui.composer")
local Confirm = require("uji.core.ui.views.confirm")
local event = require("uji.core.event")
local images = require("uji.core.images")
local Input = require("uji.core.ui.views.input")
local keys = require("uji.core.ui.keys")
local Keymap = require("uji.core.ui.keymap")
local layout = require("uji.core.ui.layout")
local model = require("uji.core.model")
local Messages = require("uji.core.ui.views.messages")
local notices = require("uji.core.notices")
local Pastes = require("uji.core.ui.paste")
local Scroll = require("uji.core.ui.scroll")
local Selection = require("uji.core.ui.selection")
local spans = require("uji.core.ui.spans")
local Stream = require("uji.core.ui.stream")
local Styles = require("uji.core.ui.styles")
local Suggest = require("uji.core.ui.views.suggest")
local sys = require("uji.sys")
local task = require("uji.core.task")
local text = require("uji.core.ui.text")
local Theme = require("uji.core.ui.theme")
local Window = require("uji.core.ui.window")

local FRAME = 1 / 60
local FLASH = 1
local MIN_PICK_ROWS = 10
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

local function above(area, input)
    if input and input.y > area.y then
        return layout.rect(area.x, area.y, area.width, input.y - area.y)
    end
    return area
end

local function exit_text(exit)
    if exit.signal then
        return "signal: " .. exit.signal
    end
    return "exit status: " .. tostring(exit.code)
end

local Ui = class()

function Ui:init()
    self.windows = {}
    self.next_window = 0
    self.keymap = Keymap()
    self.theme = Theme()
    self.composer = Composer()
    self.sends = task.sequence()
    self.stream = Stream()
    self.reasoning = ""
    self.notices = {}
    self.running = nil
    self.modal = nil
    self.capture = nil
    self.scroll = Scroll()
    self.selection = Selection()
    self.views = { messages = Messages(), input = Input() }
    self.dirty = sys.promise()
    self.suspended = false
end

function Ui:open()
    if not self.screen then
        self.screen, self.input = sys.tty.open()
        self.styles = Styles(self.screen)
    end
    return self.screen
end

function Ui:invalidate()
    if not self.dirty.settled then
        self.dirty:resolve()
    end
end

function Ui:open_window(opts)
    local window = Window(self.next_window, opts)
    self.next_window = self.next_window + 1
    local at = #self.windows + 1
    for index, existing in ipairs(self.windows) do
        if existing.priority > window.priority then
            at = index
            break
        end
    end
    table.insert(self.windows, at, window)
    self:invalidate()
    return window.id
end

function Ui:window(id)
    for index, window in ipairs(self.windows) do
        if window.id == id then
            return window, index
        end
    end
end

function Ui:close_window(id)
    local _, index = self:window(id)
    if not index then
        return false
    end
    table.remove(self.windows, index)
    self:invalidate()
    return true
end

function Ui:chrome(window)
    if window.border == "none" and window.padding == 0 then
        return { border = "none" }
    end
    return {
        border = window.border,
        padding = window.padding,
        title = window.title,
        style = window.border_color and self.styles:get({ fg = window.border_color }) or self.palette.border,
    }
end

function Ui:present(modal)
    if self.modal then
        self.modal:close()
    end
    modal.ui = self
    self.modal = modal
    self:invalidate()
    return modal
end

function Ui:ask(modal)
    return self:present(modal):wait()
end

function Ui:close_modal(modal)
    if self.modal == modal then
        self.modal = nil
        self:invalidate()
    end
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
    local frames = self.theme.loader_frames
    local elapsed = app.agent and app.agent:elapsed()
    if not elapsed or #frames == 0 then
        return ""
    end
    local interval = math.max(self.theme.loader_interval, 0.001)
    return frames[math.floor(elapsed / interval) % #frames + 1]
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
    local value = text.trim(taken)
    self:invalidate()
    if value:sub(1, 1) == "/" then
        return self:run_command(value:sub(2))
    end
    if value:sub(1, 1) == "!" then
        local shell = text.trim(value:sub(2))
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

function Ui:key(chord)
    if self.selection:clear() then
        self:invalidate()
    end
    if self.capture then
        self:captured(chord)
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
    local shown = { text = " " .. message .. " " }
    self.flashed = shown
    self:invalidate()
    task.spawn(function()
        sys.sleep(FLASH)
        if self.flashed == shown then
            self.flashed = nil
            self:invalidate()
        end
    end)
end

function Ui:copy(value)
    local count = #text.lines(value)
    if sys.clipboard.set(value) then
        self:flash("copied " .. count .. " line(s)")
        return
    end
    self.screen:write("\27]52;c;" .. sys.base64.encode(value) .. "\7")
    self:flash("copied " .. count .. " line(s) via the terminal")
end

function Ui:mouse(incoming)
    local kind = incoming.kind
    if kind == "scroll_up" then
        self:scroller():up(SCROLL_LINES)
    elseif kind == "scroll_down" then
        self:scroller():down(SCROLL_LINES)
    elseif incoming.button == "left" and kind == "down" then
        self.clicking = self.screen:clicked(incoming.row, incoming.col)
        self.selection:press(incoming.col, incoming.row, sys.os.clock())
    elseif incoming.button == "left" and kind == "drag" then
        self.clicking = nil
        self.selection:drag(incoming.col, incoming.row)
    elseif incoming.button == "left" and kind == "up" then
        local click = self.clicking
        self.clicking = nil
        local copied = self.selection:release()
        if copied then
            self:copy(copied)
        elseif click then
            click(self, incoming)
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

function Ui:fit(area)
    local rects = layout.layout(area, self.windows)
    for index, window in ipairs(self.windows) do
        local rect = rects[index]
        if window.size == "auto" and window.view ~= "messages" and rect.width > 0 then
            local content = window:boxed() and math.max(rect.width - 2, 0) or rect.width
            local rows
            if window.view == "input" then
                rows = self.views.input:rows(self, content)
            elseif window.view == "modal" then
                local modal = self.modal
                rows = modal and not modal.takeover and modal:rows(content, self) or 0
            else
                rows = #window.lines
            end
            window.fitted = rows == 0 and 0 or rows + window:chrome()
        end
    end
end

function Ui:measured(rects)
    local parts = {}
    for index, window in ipairs(self.windows) do
        local area = layout.inner(rects[index], window.border, window.padding)
        window.area = area
        parts[index] = table.concat({ window.id, area.x, area.y, area.width, area.height }, ",")
    end
    local key = table.concat(parts, ";")
    if key ~= self.measure then
        self.measure = key
        event.emit("layout_changed", {})
    end
end

function Ui:blit(screen, area, window)
    local inner = canvas.block(screen, area, self:chrome(window))
    canvas.lines(screen, inner, spans.lines(window.lines, inner.width, window.wrap, self.styles))
end

function Ui:paint()
    local screen = self.screen
    local width, height = screen:size()
    self.palette = self.styles:sync(self.theme)
    local area = layout.rect(0, 0, width, height)
    self:fit(area)
    local rects = layout.layout(area, self.windows)
    self:measured(rects)
    local modal_rect, input_rect, pane
    for index, window in ipairs(self.windows) do
        local rect = rects[index]
        local view = window.view
        if view == "messages" then
            pane = self.views.messages:draw(self, screen, rect, window)
        elseif view == "input" then
            input_rect = input_rect or rect
            self.views.input:draw(self, screen, rect, window)
        elseif view == "modal" then
            modal_rect = modal_rect or rect
        else
            self:blit(screen, rect, window)
        end
    end
    local modal = self.modal
    if modal and not modal.takeover then
        local target
        if modal.float and not (modal_rect and modal_rect.height >= MIN_PICK_ROWS) then
            target = layout.centered(area, math.floor(width * 90 / 100), math.floor(height * 80 / 100))
        else
            target = modal_rect or above(area, input_rect)
        end
        modal:draw(self, screen, target)
    end
    self.selection:sync(screen, width, height, self.palette.reverse, not modal and pane or nil)
    if self.flashed then
        local size = math.min(text.width(self.flashed.text), width)
        screen:line(0, width - size, { { self.flashed.text, self.palette.reverse } }, size)
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
            local ok, err = pcall(self.render, self)
            local problem = not ok and sys.message(err) or nil
            if problem and problem ~= self.failure then
                notices.push("render: " .. problem)
            end
            self.failure = problem
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
            sys.sleep(self.theme.loader_interval)
            if self:working() then
                event.emit("loader_ticked", {})
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
    for _, message in ipairs(notices.take()) do
        self.notices[#self.notices + 1] = message
    end
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
            self.scroll:follow()
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
            self:tick()
            self:invalidate()
        end,
        scroll_to_bottom = function()
            self.scroll:follow()
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
