use std::error::Error;

use serde_json::Value;
use uji_tests::probe;

const INPUT: &str = r#"
local app = require("uji.app")
local command = require("uji.command")
local Confirm = require("uji.ui.views.confirm")
local keys = require("uji.ui.keys")
local Keymap = require("uji.ui.keymap")
local Modal = require("uji.ui.views.modal")
local Prompt = require("uji.ui.views.prompt")
local Select = require("uji.ui.views.select")
local text = require("uji.ui.text")
local ui = require("uji.ui")

local action

function ui:run_command(line)
    action = { "command", line }
end

function ui:send(value)
    action = { "submit", value }
end

function ui:interrupt()
    action = { "interrupt" }
    return true
end

app.agent.run_shell = function(_, value)
    action = { "shell", value }
end

local settle = Modal.settle

function Modal:settle(value)
    if self.mode == "confirm" then
        action = { "confirmed", value }
    elseif self.mode == "prompt" then
        action = { "prompted", value }
    end
    return settle(self, value)
end

local function handle(chord)
    action = { "none" }
    if ui.modal then
        ui.modal:key(chord, ui)
    else
        ui:normal_key(chord)
    end
    return action
end

local function press(key)
    return handle(keys.chord(key))
end

local function typing(value)
    for char in value:gmatch(text.CHAR) do
        handle(keys.chord(char))
    end
end

local function binding(keymap, mode, spec)
    local found = keymap:get(mode, keys.parse(spec))
    return found and found.action
end
"#;

#[derive(Debug, PartialEq, Eq)]
enum KeyAction {
    None,
    Submit(String),
    Command(String),
    Shell(String),
    Prompted(String),
    Confirmed(bool),
    Interrupt,
}

fn key_action(value: &Value) -> KeyAction {
    let text = || value[1].as_str().unwrap_or_default().to_string();
    match value[0].as_str() {
        Some("submit") => KeyAction::Submit(text()),
        Some("command") => KeyAction::Command(text()),
        Some("shell") => KeyAction::Shell(text()),
        Some("prompted") => KeyAction::Prompted(text()),
        Some("confirmed") => KeyAction::Confirmed(value[1] == true),
        Some("interrupt") => KeyAction::Interrupt,
        _ => KeyAction::None,
    }
}

fn run(lua: &str) -> Result<Vec<Value>, Box<dyn Error>> {
    probe(&format!("{INPUT}\n{lua}"))
}

fn action(value: &Value) -> Option<String> {
    value.as_str().map(String::from)
}

#[test]
fn a_leading_bang_runs_a_command_rather_than_sending_it() {
    let seen = run(r#"
        typing("!cat foo.txt")
        emit(press("enter"))
        emit(ui.composer:text())
        typing("! ")
        emit(press("enter"))
    "#)
    .unwrap();
    assert_eq!(
        key_action(&seen[0]),
        KeyAction::Shell(String::from("cat foo.txt"))
    );
    assert_eq!(seen[1], "");
    assert_eq!(
        key_action(&seen[2]),
        KeyAction::None,
        "a bang with nothing after it runs nothing"
    );
}

#[test]
fn a_slash_is_a_command_and_anything_else_is_a_message() {
    let seen = run(r#"
        typing("/help")
        emit(press("enter"))
        typing("hello")
        emit(press("enter"))
    "#)
    .unwrap();
    assert_eq!(
        key_action(&seen[0]),
        KeyAction::Command(String::from("help"))
    );
    assert_eq!(
        key_action(&seen[1]),
        KeyAction::Submit(String::from("hello"))
    );
}

#[test]
fn shift_types_a_capital() {
    let seen = run(r#"
        handle(keys.chord("A", false, false, true))
        handle(keys.chord("B", false, false, true))
        typing("c")
        emit(ui.composer:text())
    "#)
    .unwrap();
    assert_eq!(seen[0], "ABc");
}

#[test]
fn a_modified_key_never_types_its_letter() {
    let seen = run(r#"
        for _, chord in ipairs({ keys.chord("w", true), keys.chord("d", false, true), keys.chord("a", true) }) do
            emit(handle(chord))
        end
        emit(ui.composer:text())
        ui:present(Select({ title = "pick", items = { "one" } }))
        typing("ab")
        handle(keys.chord("w", true))
        handle(keys.chord("d", false, true))
        emit(ui.modal.query.text)
    "#)
    .unwrap();
    for seen in &seen[..3] {
        assert_eq!(key_action(seen), KeyAction::None);
    }
    assert_eq!(seen[3], "");
    assert_eq!(seen[4], "ab");
}

#[test]
fn a_newline_is_composed_and_sent_as_one_message() {
    let seen = run(r#"
        typing("first")
        ui:act("insert_newline")
        typing("second")
        emit(ui.composer:text())
        emit(press("enter"))
        typing("first \\")
        emit(press("enter"))
        typing("second")
        emit(press("enter"))
    "#)
    .unwrap();
    assert_eq!(seen[0], "first\nsecond");
    assert_eq!(
        key_action(&seen[1]),
        KeyAction::Submit(String::from("first\nsecond"))
    );
    assert_eq!(
        key_action(&seen[2]),
        KeyAction::None,
        "a trailing backslash continues instead of sending"
    );
    assert_eq!(
        key_action(&seen[3]),
        KeyAction::Submit(String::from("first \nsecond"))
    );
}

#[test]
fn up_moves_within_a_multi_line_draft_before_it_recalls() {
    let seen = run(r#"
        typing("first")
        ui:act("insert_newline")
        typing("second")
        ui:act("history_prev")
        emit(ui.composer.line.cursor)
        ui:act("history_next")
        emit(ui.composer.line.cursor)
    "#)
    .unwrap();
    assert_eq!(seen[0], 5);
    assert_eq!(seen[1], 11);
}

#[test]
fn escape_clears_a_draft_and_then_interrupts() {
    let seen = run(r#"
        typing("half written")
        emit(press("esc"))
        emit(ui.composer:text())
        emit(press("esc"))
    "#)
    .unwrap();
    assert_eq!(key_action(&seen[0]), KeyAction::None);
    assert_eq!(seen[1], "");
    assert_eq!(key_action(&seen[2]), KeyAction::Interrupt);
}

#[test]
fn a_confirm_answers_the_letter_but_not_the_chord() {
    let seen = run(r#"
        ui:present(Confirm({ title = "run?", body = "ls" }))
        emit(handle(keys.chord("y", true)))
        emit(press("y"))
        ui:present(Confirm({ title = "run?", body = "ls" }))
        emit(handle(keys.chord("n", true)))
        emit(press("n"))
    "#)
    .unwrap();
    assert_eq!(key_action(&seen[0]), KeyAction::None);
    assert_eq!(key_action(&seen[1]), KeyAction::Confirmed(true));
    assert_eq!(
        key_action(&seen[2]),
        KeyAction::None,
        "<C-n> walks the list"
    );
    assert_eq!(key_action(&seen[3]), KeyAction::Confirmed(false));
}

#[test]
fn a_prompt_answers_what_was_typed_into_it() {
    let seen = run(r#"
        ui:present(Prompt({ title = "key" }))
        typing("ab")
        handle(keys.chord("y", true))
        emit(press("enter"))
    "#)
    .unwrap();
    assert_eq!(
        key_action(&seen[0]),
        KeyAction::Prompted(String::from("ab"))
    );
}

#[test]
fn tab_completes_a_suggestion() {
    let seen = run(r#"
        command.suggestions = function()
            return { { name = "models", desc = "pick the default model" } }
        end
        typing("/mod")
        emit(ui:mode())
        handle(keys.chord("w", true))
        emit(ui.composer:text())
        press("tab")
        emit(ui.composer:text())
    "#)
    .unwrap();
    assert_eq!(seen[0], "suggest");
    assert_eq!(seen[1], "/mod", "a chord must not type into the composer");
    assert_eq!(seen[2], "/models ");
}

#[test]
fn typing_in_a_picker_reranks_it_and_a_page_key_walks_it() {
    let seen = run(r#"
        ui:present(Select({ title = "pick", items = { "alpha", "beta" } }))
        emit(#ui.modal.matches)
        typing("alp")
        emit(#ui.modal.matches)
        for _ = 1, 3 do
            press("backspace")
        end
        emit(#ui.modal.matches)
        local items = {}
        for at = 0, 29 do
            items[#items + 1] = "item " .. at
        end
        ui:present(Select({ title = "pick", items = items }))
        press("pagedown")
        emit(ui.modal.cursor - 1)
        press("pageup")
        emit(ui.modal.cursor - 1)
    "#)
    .unwrap();
    assert_eq!(seen[0], 2);
    assert_eq!(seen[1], 1);
    assert_eq!(seen[2], 2);
    assert!(
        seen[3].as_u64().unwrap_or_default() > 0,
        "page down should move down the list"
    );
    assert_eq!(seen[4], 0);
}

#[test]
fn the_default_bindings_follow_the_mode() {
    let seen = run(r#"
        local keymap = Keymap()
        emit(binding(keymap, "normal", "<C-w>"))
        emit(binding(keymap, "select", "<C-u>"))
        emit(binding(keymap, "confirm", "<C-w>"))
        emit(binding(keymap, "normal", "<C-p>"))
        emit(binding(keymap, "select", "<C-p>"))
        for _, spec in ipairs({ "<S-CR>", "<A-CR>", "<C-j>" }) do
            emit(binding(keymap, "normal", spec))
        end
        for _, mode in ipairs({ "normal", "confirm", "select", "prompt", "suggest" }) do
            emit(binding(keymap, mode, "<C-c>"))
        end
    "#)
    .unwrap();
    assert_eq!(action(&seen[0]).as_deref(), Some("delete_word_back"));
    assert_eq!(action(&seen[1]).as_deref(), Some("delete_to_start"));
    assert!(
        action(&seen[2]).is_none(),
        "there is no text to edit in a confirm"
    );
    assert_eq!(action(&seen[3]).as_deref(), Some("history_prev"));
    assert_eq!(
        action(&seen[4]).as_deref(),
        Some("modal_up"),
        "up means the list in a modal"
    );
    for (spec, seen) in ["<S-CR>", "<A-CR>", "<C-j>"].iter().zip(&seen[5..8]) {
        assert_eq!(
            action(seen).as_deref(),
            Some("insert_newline"),
            "{spec} should insert a newline"
        );
    }
    for seen in &seen[8..13] {
        assert_eq!(action(seen).as_deref(), Some("quit"));
    }
}

#[test]
fn a_binding_names_a_key_and_round_trips_through_its_name() {
    let seen = run(r#"
        local keymap = Keymap()
        local upper = keys.chord("W", true, false, true)
        emit(keymap:get("normal", upper).action)
        for _, spec in ipairs({ "<C-w>", "<A-CR>", "<S-CR>", "<C-a>", "x" }) do
            local chord = keys.parse(spec)
            local described = chord and keys.describe(chord) or ""
            local again = keys.parse(described)
            local same = chord ~= nil and again ~= nil
            for _, field in ipairs({ "key", "ctrl", "alt", "shift" }) do
                same = same and chord[field] == again[field]
            end
            emit({ spec, chord ~= nil, described, same })
        end
    "#)
    .unwrap();
    assert_eq!(seen[0], "delete_word_back");
    for row in &seen[1..] {
        let spec = &row[0];
        let described = &row[2];
        assert!(row[1] == true, "{spec} should parse");
        assert!(row[3] == true, "{spec} to {described}");
    }
}
