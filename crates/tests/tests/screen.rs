use std::error::Error;

use uji_tests::Sandbox;

const CURSOR: char = '\u{2588}';
const MASK: char = '\u{2022}';

const SCREEN: &str = r#"
local app = require("uji.app")
local Confirm = require("uji.ui.views.confirm")
local keys = require("uji.ui.keys")
local Pick = require("uji.ui.views.pick")
local Prompt = require("uji.ui.views.prompt")
local Select = require("uji.ui.views.select")
local text = require("uji.ui.text")
local ui = require("uji.ui")

ui:open_window({ view = "messages", size = "fill" })
ui:open_window({ view = "input", split = "bottom", size = "auto" })

local function handle(chord)
    if ui.modal then
        ui.modal:key(chord, ui)
    else
        ui:normal_key(chord)
    end
end

local function typing(value)
    for char in value:gmatch(text.CHAR) do
        handle(keys.chord(char))
    end
end

local function screen()
    ui:paint()
    local _, height = ui.screen:size()
    local rows = {}
    for row = 0, height - 1 do
        rows[#rows + 1] = ui.screen:text(row)
    end
    return table.concat(rows)
end
"#;

fn screen(width: u16, height: u16, lua: &str) -> Result<Vec<String>, Box<dyn Error>> {
    Ok(Sandbox::new("screen")?
        .probe_on(width, height, &format!("{SCREEN}\n{lua}"))?
        .iter()
        .map(|value| value.as_str().unwrap_or_default().to_string())
        .collect())
}

#[test]
fn the_draft_is_drawn_with_the_cursor_in_it() {
    let seen = screen(
        40,
        8,
        r#"
        typing("hello")
        handle(keys.chord("left"))
        handle(keys.chord("left"))
        emit(screen())
    "#,
    )
    .unwrap();
    let text = &seen[0];
    assert!(
        text.contains(&format!("hel{CURSOR}lo")),
        "the draft and its cursor should be on screen"
    );
}

#[test]
fn a_hidden_prompt_shows_no_characters() {
    let seen = screen(
        40,
        10,
        r#"
        ui:present(Prompt({ title = "api key", value = "", hidden = true }))
        typing("hunter2")
        handle(keys.chord("left"))
        emit(screen())
    "#,
    )
    .unwrap();
    let text = &seen[0];
    assert!(text.contains("api key"), "the title should be drawn");
    assert!(text.contains(MASK), "the value should be masked");
    assert!(!text.contains("hunter2"));
    assert!(!text.contains('2'));
    assert!(text.contains(CURSOR), "the cursor should still be drawn");
}

#[test]
fn a_select_draws_its_items_and_the_query() {
    let seen = screen(
        40,
        12,
        r#"
        ui:present(Select({ title = "pick one", items = { "alpha", "beta" } }))
        typing("al")
        emit(screen())
    "#,
    )
    .unwrap();
    let text = &seen[0];
    assert!(text.contains("pick one"), "title missing");
    assert!(text.contains("alpha"), "the matching item is missing");
    assert!(!text.contains("beta"), "a filtered item is still drawn");
    assert!(
        text.contains(&format!("al{CURSOR}")),
        "the query and cursor are missing"
    );
}

#[test]
fn a_picker_draws_its_counts_and_preview() {
    let seen = screen(
        60,
        20,
        r#"
        ui:present(Pick({ title = "files", items = { "one", "two" } }))
        typing("on")
        ui.modal.preview = { "a preview line" }
        ui.modal.previewed = ui.modal:chosen()
        emit(screen())
    "#,
    )
    .unwrap();
    let text = &seen[0];
    assert!(text.contains("files"), "title missing");
    assert!(text.contains("1/2"), "the match counts are missing");
    assert!(text.contains("a preview line"), "the preview is missing");
}

#[test]
fn a_long_message_wraps_to_the_width() {
    let width = 30;
    let seen = screen(
        width,
        20,
        r#"
        app.session:append({ type = "user", text = string.rep("wrap ", 40) })
        emit(screen())
    "#,
    )
    .unwrap();
    let text = &seen[0];
    let rows: Vec<String> = text
        .as_str()
        .chars()
        .collect::<Vec<_>>()
        .chunks(usize::from(width))
        .map(|row| row.iter().collect::<String>().trim_end().to_string())
        .collect();
    let wrapped = rows.iter().filter(|row| row.contains("wrap")).count();
    assert!(wrapped > 1, "a long message should take more than one row");
    assert!(
        rows.iter()
            .all(|row| row.chars().count() <= usize::from(width)),
        "a row should never run past the width"
    );
}

#[test]
fn a_tall_confirm_keeps_its_choices_on_screen_and_scrolls_its_body() {
    let seen = screen(
        60,
        20,
        r#"
        local body = {}
        for n = 1, 200 do
            body[n] = "content line " .. n
        end
        ui:present(Confirm({ title = "Write big.txt?", body = table.concat(body, "\n") }))
        emit(screen())
        handle(keys.chord("end"))
        emit(screen())
    "#,
    )
    .unwrap();
    let top = &seen[0];
    assert!(top.contains("content line 1 "));
    assert!(top.contains("of 200, scroll for more"));
    assert!(top.contains("1. Yes, proceed"));
    assert!(top.contains("2. No, and tell uji"));
    let bottom = &seen[1];
    assert!(bottom.contains("content line 200"));
    assert!(!bottom.contains("content line 1 "));
    assert!(bottom.contains("1. Yes, proceed"));
}
