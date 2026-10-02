local actions = require("uji.core.ui.actions")
local app = require("uji.core.app")
local check = require("uji.core.check")
local images = require("uji.core.images")
local keys = require("uji.core.ui.keys")
local Keymap = require("uji.core.ui.keymap")
local model = require("uji.core.model")
local notices = require("uji.core.notices")
local Pick = require("uji.core.ui.views.pick")
local plugin = require("uji.core.plugin")
local process = require("uji.core.system.process")
local Prompt = require("uji.core.ui.views.prompt")
local Registry = require("uji.core.registry")
local Select = require("uji.core.ui.views.select")
local task = require("uji.core.task")
local ui = require("uji.core.ui")
local Window = require("uji.core.ui.window")

local segments = plugin.track(Registry(plugin.current))

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

local function draw(name, render, out)
    local ok, value = pcall(render)
    if not ok then
        notices.push("status segment " .. name .. ": " .. tostring(value))
    elseif value ~= nil then
        out[#out + 1] = value
    end
end

local function window(id)
    local found = ui:window(id)
    return found
end

local M = {}

M.ui = {
    open_win = function(opts)
        return raise(pcall(ui.open_window, ui, opts))
    end,
    close_win = function(id)
        return ui:close_window(id)
    end,
    list_wins = function()
        local out = {}
        for index, found in ipairs(ui.windows) do
            local area = found.area or {}
            out[index] = {
                id = found.id,
                name = found.name,
                view = found.view,
                split = found.split,
                size = found.size,
                priority = found.priority,
                float = found.float ~= nil,
                x = area.x,
                y = area.y,
                width = area.width,
                height = area.height,
            }
        end
        return out
    end,
    size = function()
        if ui.screen then
            return ui.screen:size()
        end
    end,
    set_lines = function(id, lines)
        local parsed = raise(pcall(Window.lines, lines))
        local found = window(id)
        if found then
            found.lines = parsed
            ui:invalidate()
        end
    end,
    clear = function(id)
        local found = window(id)
        if found then
            found.lines = {}
            ui:invalidate()
        end
    end,
    set_size = function(id, size)
        local parsed = raise(pcall(Window.size, size))
        local found = window(id)
        if found then
            found.size = parsed
            ui:invalidate()
        end
    end,
    set_title = function(id, title)
        local found = window(id)
        if found then
            found.title = title
            ui:invalidate()
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
}

M.status = {
    provider = function()
        return model.current.name
    end,
    model = function()
        return model.current.model
    end,
    effort = function()
        local effort = model.current.effort
        return effort ~= "off" and effort or nil
    end,
    context = function()
        return {
            used = app.session and app.session:used_tokens() or 0,
            window = model.window(),
        }
    end,
    queue = function()
        local out = {}
        for index, queued in ipairs(app.agent and app.agent.queue or {}) do
            out[index] = queued.text
        end
        return out
    end,
    state = function()
        return ui:working() and "working" or "idle"
    end,
    elapsed = function()
        return app.agent and app.agent:elapsed()
    end,
    loader_frame = function()
        return ui:loader_frame()
    end,
    add = function(name, render, opts)
        if type(name) ~= "string" or type(render) ~= "function" then
            error("uji.status.add needs a name and a function", 2)
        end
        segments:add(name, render, opts)
    end,
    remove = function(name)
        return segments:remove(name)
    end,
    list = function()
        return segments:names()
    end,
    render = function(names)
        local out = {}
        if names == nil then
            for name, render in segments:each() do
                draw(name, render, out)
            end
            return out
        end
        for _, name in ipairs(strings(names, "uji.status.render")) do
            local render = segments:get(name)
            if render then
                draw(name, render, out)
            end
        end
        return out
    end,
}

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
uji.status = M.status
uji.input = M.input
uji.keymap = M.keymap
uji.action = M.action
