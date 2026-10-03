local app = require("uji.core.app")
local command = require("uji.core.command")
local Confirm = require("uji.core.ui.views.confirm")
local keys = require("uji.core.ui.keys")
local Keymap = require("uji.core.ui.keymap")
local Modal = require("uji.core.ui.views.modal")
local Prompt = require("uji.core.ui.views.prompt")
local Select = require("uji.core.ui.views.select")
local screen = require("support.ui")
local ui = require("uji.core.ui")

local NONE = { "none" }

local action

before_each(function()
    ui.run_command = function(_, line)
        action = { "command", line }
    end
    ui.send = function(_, value)
        action = { "submit", value }
    end
    ui.interrupt = function()
        action = { "interrupt" }
        return true
    end
    app.agent.run_shell = function(_, value)
        action = { "shell", value }
    end
    local settle = Modal.settle
    function Modal:settle(value)
        if self.mode == "confirm" then
            action = { "confirmed", value == true }
        elseif self.mode == "prompt" then
            action = { "prompted", value }
        end
        return settle(self, value)
    end
end)

local function handle(chord)
    action = NONE
    screen.handle(chord)
    return action
end

local function press(key)
    return handle(keys.chord(key))
end

local function binding(keymap, mode, spec)
    local found = keymap:get(mode, keys.parse(spec))
    return found and found.action
end

it("runs a leading bang as a command rather than sending it", function()
    screen.typing("!cat foo.txt")
    assert.same({ "shell", "cat foo.txt" }, press("enter"))
    assert.equal("", ui.composer:text())
    screen.typing("! ")
    assert.same(NONE, press("enter"), "a bang with nothing after it runs nothing")
end)

it("treats a slash as a command and anything else as a message", function()
    screen.typing("/help")
    assert.same({ "command", "help" }, press("enter"))
    screen.typing("hello")
    assert.same({ "submit", "hello" }, press("enter"))
end)

it("types a capital with shift", function()
    handle(keys.chord("A", false, false, true))
    handle(keys.chord("B", false, false, true))
    screen.typing("c")
    assert.equal("ABc", ui.composer:text())
end)

it("never types the letter of a modified key", function()
    for _, chord in ipairs({ keys.chord("w", true), keys.chord("d", false, true), keys.chord("a", true) }) do
        assert.same(NONE, handle(chord))
    end
    assert.equal("", ui.composer:text())
    ui:present(Select({ title = "pick", items = { "one" } }))
    screen.typing("ab")
    handle(keys.chord("w", true))
    handle(keys.chord("d", false, true))
    assert.equal("ab", ui.modal.query.text)
end)

it("composes a newline and sends it as one message", function()
    screen.typing("first")
    ui:act("insert_newline")
    screen.typing("second")
    assert.equal("first\nsecond", ui.composer:text())
    assert.same({ "submit", "first\nsecond" }, press("enter"))
    screen.typing("first \\")
    assert.same(NONE, press("enter"), "a trailing backslash continues instead of sending")
    screen.typing("second")
    assert.same({ "submit", "first \nsecond" }, press("enter"))
end)

it("moves up within a multi-line draft before it recalls", function()
    screen.typing("first")
    ui:act("insert_newline")
    screen.typing("second")
    ui:act("history_prev")
    assert.equal(5, ui.composer.line.cursor)
    ui:act("history_next")
    assert.equal(11, ui.composer.line.cursor)
end)

it("clears a draft with escape and then interrupts", function()
    screen.typing("half written")
    assert.same(NONE, press("esc"))
    assert.equal("", ui.composer:text())
    assert.same({ "interrupt" }, press("esc"))
end)

it("answers a confirm with the letter but not the chord", function()
    ui:present(Confirm({ title = "run?", body = "ls" }))
    assert.same(NONE, handle(keys.chord("y", true)))
    assert.same({ "confirmed", true }, press("y"))
    ui:present(Confirm({ title = "run?", body = "ls" }))
    assert.same(NONE, handle(keys.chord("n", true)), "<C-n> walks the list")
    assert.same({ "confirmed", false }, press("n"))
end)

it("answers a prompt with what was typed into it", function()
    ui:present(Prompt({ title = "key" }))
    screen.typing("ab")
    handle(keys.chord("y", true))
    assert.same({ "prompted", "ab" }, press("enter"))
end)

it("completes a suggestion with tab", function()
    command.suggestions = function()
        return { { name = "models", desc = "pick the default model" } }
    end
    screen.typing("/mod")
    assert.equal("suggest", ui:mode())
    handle(keys.chord("w", true))
    assert.equal("/mod", ui.composer:text(), "a chord must not type into the composer")
    press("tab")
    assert.equal("/models ", ui.composer:text())
end)

it("reranks a picker as you type and walks it with a page key", function()
    ui:present(Select({ title = "pick", items = { "alpha", "beta" } }))
    assert.equal(2, #ui.modal.matches)
    screen.typing("alp")
    assert.equal(1, #ui.modal.matches)
    for _ = 1, 3 do
        press("backspace")
    end
    assert.equal(2, #ui.modal.matches)
    local items = {}
    for at = 0, 29 do
        items[#items + 1] = "item " .. at
    end
    ui:present(Select({ title = "pick", items = items }))
    press("pagedown")
    assert.is_true(ui.modal.cursor - 1 > 0, "page down should move down the list")
    press("pageup")
    assert.equal(0, ui.modal.cursor - 1)
end)

it("follows the mode in the default bindings", function()
    local keymap = Keymap()
    assert.equal("delete_word_back", binding(keymap, "normal", "<C-w>"))
    assert.equal("delete_to_start", binding(keymap, "select", "<C-u>"))
    assert.is_nil(binding(keymap, "confirm", "<C-w>"), "there is no text to edit in a confirm")
    assert.equal("history_prev", binding(keymap, "normal", "<C-p>"))
    assert.equal("modal_up", binding(keymap, "select", "<C-p>"), "up means the list in a modal")
    for _, spec in ipairs({ "<S-CR>", "<A-CR>", "<C-j>" }) do
        assert.equal("insert_newline", binding(keymap, "normal", spec), spec .. " should insert a newline")
    end
    for _, mode in ipairs({ "normal", "confirm", "select", "prompt", "suggest" }) do
        assert.equal("quit", binding(keymap, mode, "<C-c>"))
    end
end)

it("names a key in a binding and round trips it through its name", function()
    local keymap = Keymap()
    assert.equal("delete_word_back", keymap:get("normal", keys.chord("W", true, false, true)).action)
    for _, spec in ipairs({ "<C-w>", "<A-CR>", "<S-CR>", "<C-a>", "x" }) do
        local chord = keys.parse(spec)
        assert.is_not_nil(chord, spec .. " should parse")
        local described = keys.describe(chord)
        local again = keys.parse(described)
        assert.is_not_nil(again, spec .. " to " .. described)
        for _, field in ipairs({ "key", "ctrl", "alt", "shift" }) do
            assert.equal(chord[field], again[field], spec .. " to " .. described)
        end
    end
end)
