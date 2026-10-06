local actions = require("uji.core.ui.actions")
local app = require("uji.core.app")
local check = require("uji.core.check")
local ito = require("ito")
local images = require("uji.core.images")
local keys = require("uji.core.ui.keys")
local Keymap = require("uji.core.ui.keymap")
local Overlay = require("uji.core.ui.views.overlay")
local markdown = require("uji.core.ui.markdown")
local Pick = require("uji.core.ui.views.pick")
local process = require("uji.core.system.process")
local Prompt = require("uji.core.ui.views.prompt")
local Select = require("uji.core.ui.views.select")
local task = require("uji.core.task")
local ui = require("uji.core.ui")

local function raise(ok, ...)
    if not ok then
        error(..., 3)
    end
    return ...
end

local function strings(list, what)
    if list == nil then
        return {}
    end
    if type(list) ~= "table" then
        error(what .. " must be a list of strings", 3)
    end
    for _, item in ipairs(list) do
        if type(item) ~= "string" then
            error(what .. " must be a list of strings", 3)
        end
    end
    return list
end

local function callable(value)
    local meta = type(value) == "table" and getmetatable(value)
    return type(value) == "function" or (meta and meta.__call ~= nil)
end

local M = {}

M.ui = {
    toolbar = function(items)
        if type(items) ~= "table" or ito.is_view(items) then
            error("uji.ui.toolbar takes a list of ito.ToolbarItem", 2)
        end
        for index, item in pairs(items) do
            if type(index) ~= "number" or (item and not ito.is_toolbar_item(item)) then
                error("uji.ui.toolbar takes a list of ito.ToolbarItem", 2)
            end
        end
        local declared = ui:toolbar(items)
        return {
            remove = function()
                return ui:remove_toolbar(declared)
            end,
        }
    end,
    size = function()
        if ui.screen then
            return ui.screen:size()
        end
    end,
    select = task.callback(function(opts)
        check.options(opts, "uji.ui.select")
        strings(opts.items, "items")
        return ui:ask(Select(opts))
    end),
    pick = task.callback(function(opts)
        check.options(opts, "uji.ui.pick")
        strings(opts.items, "items")
        return ui:ask(Pick(opts))
    end),
    prompt = task.callback(function(opts)
        check.options(opts, "uji.ui.prompt")
        return ui:ask(Prompt(opts))
    end),
    confirm = task.callback(function(opts)
        check.options(opts, "uji.ui.confirm")
        return ui:confirm(opts)
    end),
    overlay = function(content, opts)
        if not callable(content) then
            error("uji.ui.overlay needs a function that returns a view", 2)
        end
        local overlay = ui:present(Overlay(content, opts))
        return {
            close = function(_, value)
                overlay:settle(value)
            end,
            wait = function()
                return overlay:wait()
            end,
        }
    end,
    exec = function(cmd)
        ui:exec(process.argv(cmd))
    end,
    toggle_thinking = function()
        ui:toggle_thinking()
    end,
    configure = function(opts)
        raise(pcall(ui.theme.configure, ui.theme, opts))
        ui:invalidate()
    end,
    theme = function()
        return ui.theme.selection
    end,
    save_theme = function(name)
        check.name(name, "uji.ui.save_theme")
        ui.theme:save(name)
    end,
}

M.ui.Markdown = function(text)
    if type(text) ~= "string" then
        error("uji.ui.Markdown needs a string", 2)
    end
    return markdown.Markdown({ text = text })
end

M.ui.Screen = require("uji.core.ui.screen").Screen
M.ui.Activity = require("uji.core.ui.activity")
M.ui.Input = require("uji.core.ui.input")
M.ui.Flash = require("uji.core.ui.flash")
M.ui.UserMessage = require("uji.core.ui.transcript.user")
M.ui.ToolCall = require("uji.core.ui.transcript.tool_call")
M.ui.ToolOutput = require("uji.core.ui.transcript.tool_output")
M.ui.Shell = require("uji.core.ui.transcript.shell")
M.ui.SystemMessage = require("uji.core.ui.transcript.system")
M.ui.ErrorMessage = require("uji.core.ui.transcript.error")
M.ui.Notice = require("uji.core.ui.transcript.notice")
M.ui.Thinking = require("uji.core.ui.transcript.thinking")
M.ui.Queued = require("uji.core.ui.transcript.queued")
M.ui.Compaction = require("uji.core.ui.transcript.compaction")
M.ui.Running = require("uji.core.ui.transcript.running")
M.ui.Partial = require("uji.core.ui.transcript.partial")
M.ui.Jump = require("uji.core.ui.transcript.jump")
M.ui.Paragraph = require("uji.core.ui.markdown.paragraph")
M.ui.Heading = require("uji.core.ui.markdown.heading")
M.ui.CodeBlock = require("uji.core.ui.markdown.code_block")
M.ui.MathBlock = require("uji.core.ui.markdown.math_block")
M.ui.TableRow = require("uji.core.ui.markdown.table_row")
M.ui.Rule = require("uji.core.ui.markdown.rule")
M.ui.SelectList = require("uji.core.ui.pickers.select_list")
M.ui.PromptField = require("uji.core.ui.pickers.prompt_field")
M.ui.Suggestions = require("uji.core.ui.pickers.suggestions")
M.ui.Approval = require("uji.core.ui.pickers.approval")
M.ui.Picker = require("uji.core.ui.pickers.picker")
M.ui.Sessions = require("uji.core.ui.pickers.sessions")

M.input = {
    get = function()
        return ui.composer:text()
    end,
    set = function(text)
        ui:set_input(tostring(text))
    end,
    append = function(text)
        ui:set_input(ui.composer:text() .. tostring(text))
    end,
    clear = function()
        ui:set_input("")
    end,
    attach = task.callback(function(file)
        if type(file) ~= "string" then
            error("uji.input.attach needs a path", 3)
        end
        local image, err = images.file(file, app.directory())
        if not image then
            return nil, err
        end
        ui:attach(image)
        return true
    end),
    capture = function(handler)
        if type(handler) ~= "function" then
            error("uji.input.capture needs a function", 2)
        end
        ui.capture = handler
    end,
    release = function()
        ui.capture = nil
    end,
}

local function target(mode, key)
    if not Keymap.valid(mode) then
        error("unknown keymap mode: " .. tostring(mode), 3)
    end
    local chord = keys.parse(key)
    if not chord then
        error("cannot parse key: " .. tostring(key), 3)
    end
    return chord
end

M.keymap = {
    add = function(mode, key, binding)
        local chord = target(mode, key)
        if type(binding) == "function" then
            local name = mode .. " " .. keys.describe(chord)
            actions.added:add(name, binding)
            binding = { action = name }
        elseif type(binding) == "string" then
            binding = { action = binding }
        elseif type(binding) == "table" and type(binding.command) == "string" then
            binding = { command = binding.command }
        elseif type(binding) == "table" and type(binding.action) == "string" then
            binding = { action = binding.action }
        else
            error('binding must be an action name, a function, or { command = "..." }', 2)
        end
        ui.keymap:set(mode, chord, binding)
    end,
    remove = function(mode, key)
        ui.keymap:set(mode, target(mode, key), { unbound = true })
    end,
    reset = function()
        ui.keymap:reset()
    end,
    list = function()
        return ui.keymap:rows()
    end,
}

M.action = {
    add = actions.add,
    remove = actions.remove,
    list = actions.list,
}

uji.ui = M.ui
uji.input = M.input
uji.keymap = M.keymap
uji.action = M.action
