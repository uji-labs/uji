local class = require("uji.core.class")
local keys = require("uji.core.ui.keys")

local MODES = { "normal", "confirm", "select", "prompt", "suggest" }
local EDIT = { "normal", "suggest", "prompt", "select" }
local LIST = { "select", "suggest", "confirm" }
local COMPOSE = { "normal" }

local DEFAULTS = {
    { MODES, "<C-c>", "quit" },
    { EDIT, "<C-a>", "cursor_start" },
    { EDIT, "<C-e>", "cursor_end" },
    { EDIT, "<C-b>", "cursor_left" },
    { EDIT, "<C-f>", "cursor_right" },
    { EDIT, "<A-b>", "word_left" },
    { EDIT, "<A-f>", "word_right" },
    { EDIT, "<C-h>", "backspace" },
    { EDIT, "<C-d>", "delete_forward" },
    { EDIT, "<C-w>", "delete_word_back" },
    { EDIT, "<A-BS>", "delete_word_back" },
    { EDIT, "<A-d>", "delete_word_forward" },
    { EDIT, "<C-u>", "delete_to_start" },
    { EDIT, "<C-k>", "delete_to_end" },
    { EDIT, "<C-y>", "yank" },
    { EDIT, "<C-t>", "transpose" },
    { COMPOSE, "<C-p>", "history_prev" },
    { COMPOSE, "<C-n>", "history_next" },
    { LIST, "<C-p>", "modal_up" },
    { LIST, "<C-n>", "modal_down" },
    { LIST, "<C-g>", "modal_cancel" },
    { COMPOSE, "<S-CR>", "insert_newline" },
    { COMPOSE, "<A-CR>", "insert_newline" },
    { COMPOSE, "<C-j>", "insert_newline" },
    { COMPOSE, "<C-v>", "paste_image" },
}

local Keymap = class()

Keymap.MODES = MODES

function Keymap.valid(mode)
    for _, known in ipairs(MODES) do
        if known == mode then
            return true
        end
    end
    return false
end

function Keymap:init()
    self:reset()
end

function Keymap:reset()
    self.map = {}
    for _, mode in ipairs(MODES) do
        self.map[mode] = {}
    end
    for _, default in ipairs(DEFAULTS) do
        local chord = keys.parse(default[2])
        for _, mode in ipairs(default[1]) do
            self:set(mode, chord, { action = default[3] })
        end
    end
end

function Keymap:set(mode, chord, binding)
    self.map[mode][keys.id(chord)] = binding
end

function Keymap:get(mode, chord)
    return self.map[mode][keys.id(chord)]
end

function Keymap:rows()
    local rows = {}
    for _, mode in ipairs(MODES) do
        local ids = {}
        for id in pairs(self.map[mode]) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local binding = self.map[mode][id]
            rows[#rows + 1] = {
                mode = mode,
                key = id,
                action = binding.action,
                command = binding.command,
                unbound = binding.unbound,
            }
        end
    end
    return rows
end

return Keymap
