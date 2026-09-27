local Line = require("uji.ui.line")
local Registry = require("uji.registry")
local plugin = require("uji.plugin")

local function edit(change)
    return function(ui)
        ui:edit(change)
    end
end

local function scroll(move)
    return function(ui)
        move(ui:scroller())
    end
end

local function confirm(apply)
    return function(ui)
        local modal = ui.modal
        if modal and modal.mode == "confirm" then
            apply(modal)
        end
    end
end

local RUN = {
    nothing = function() end,
    quit = function(ui)
        ui:quit()
    end,
    interrupt = function(ui)
        ui:interrupt()
    end,
    toggle_thinking = function(ui)
        ui:toggle_thinking()
    end,
    submit = function(ui)
        ui:submit()
    end,
    clear_input = function(ui)
        ui:clear_input()
    end,
    backspace = function(ui)
        ui:backspace()
    end,
    delete_forward = edit(Line.delete_forward),
    delete_word_back = edit(Line.delete_word_back),
    delete_word_forward = edit(Line.delete_word_forward),
    delete_to_start = edit(Line.delete_to_start),
    delete_to_end = edit(Line.delete_to_end),
    yank = edit(Line.yank),
    transpose = edit(Line.transpose),
    insert_newline = function(ui)
        ui:insert("\n")
    end,
    cursor_left = edit(Line.left),
    cursor_right = edit(Line.right),
    cursor_start = edit(Line.home),
    cursor_end = edit(Line.tail),
    word_left = edit(Line.word_left),
    word_right = edit(Line.word_right),
    scroll_up = scroll(function(target)
        target:up(1)
    end),
    scroll_down = scroll(function(target)
        target:down(1)
    end),
    page_up = scroll(function(target)
        target:up(math.max(target.viewport, 1))
    end),
    page_down = scroll(function(target)
        target:down(math.max(target.viewport, 1))
    end),
    scroll_top = scroll(function(target)
        target:top()
    end),
    scroll_bottom = scroll(function(target)
        target:follow()
    end),
    history_prev = function(ui)
        ui:history(-1)
    end,
    history_next = function(ui)
        ui:history(1)
    end,
    modal_up = function(ui)
        if ui.modal then
            ui.modal:move(-1)
        end
    end,
    modal_down = function(ui)
        if ui.modal then
            ui.modal:move(1)
        end
    end,
    modal_accept = function(ui)
        if ui.modal then
            ui.modal:accept()
        else
            ui:submit()
        end
    end,
    modal_cancel = function(ui)
        if ui.modal then
            ui.modal:cancel()
        elseif not ui:interrupt() then
            ui:quit()
        end
    end,
    suggest_complete = function(ui)
        if ui.modal and ui.modal.mode == "suggest" then
            ui.modal:complete()
        end
    end,
    confirm_allow = confirm(function(modal)
        modal:settle(true)
    end),
    confirm_deny = confirm(function(modal)
        modal:settle(false)
    end),
    confirm_toggle = confirm(function(modal)
        modal:toggle()
    end),
}

local M = {
    RUN = RUN,
    added = plugin.track(Registry(plugin.current)),
}

function M.builtin(name)
    return RUN[name] ~= nil
end

function M.add(name, handler)
    if type(name) ~= "string" or name == "" then
        error("uji.action.add needs a name", 2)
    end
    if type(handler) ~= "function" then
        error("uji.action.add needs a function", 2)
    end
    if RUN[name] then
        error("action " .. name .. " is built in and cannot be replaced", 2)
    end
    M.added:add(name, handler)
end

function M.remove(name)
    return M.added:remove(name)
end

function M.get(name)
    return M.added:get(name)
end

function M.list()
    local names, seen = {}, {}
    for name in pairs(RUN) do
        names[#names + 1] = name
        seen[name] = true
    end
    for _, name in ipairs(M.added:names()) do
        if not seen[name] then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

return M
