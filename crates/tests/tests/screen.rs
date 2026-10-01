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

#[test]
fn a_copied_selection_has_no_empty_line_at_either_end() {
    let seen = uji_tests::probe(
        r#"
        local Selection = require("uji.ui.selection")
        local selection = Selection()
        selection.rows = { [0] = "first line", [1] = "second", [2] = "", [3] = "fourth" }
        selection:press(0, 0, 0)
        selection:drag(0, 1)
        emit(selection:release())
        selection:clear()
        selection:press(10, 0, 10)
        selection:drag(6, 1)
        emit(selection:release())
        selection:clear()
        selection:press(0, 1, 20)
        selection:drag(6, 3)
        emit(selection:release())
        "#,
    )
    .unwrap();
    assert_eq!(
        seen[0], "first line",
        "a drag that ends at the start of the next row"
    );
    assert_eq!(
        seen[1], "second",
        "a drag that starts past the end of a line"
    );
    assert_eq!(
        seen[2], "second\n\nfourth",
        "blank lines inside the selection stay"
    );
}

#[test]
fn copying_a_selection_leaves_the_transcript_in_place() {
    let seen = screen(
        40,
        12,
        r#"
        local sys = require("uji.sys")
        local copied
        sys.clipboard.set = function(value)
            copied = value
            return true
        end
        for index = 1, 30 do
            app.session:append({ type = "user", text = "line " .. index })
        end
        local function rows()
            ui.screen:clear()
            ui:paint()
            local _, height = ui.screen:size()
            local out = {}
            for row = 0, height - 1 do
                out[#out + 1] = ui.screen:text(row)
            end
            return table.concat(out, "\n")
        end
        local before = rows()
        emit(before)
        local row
        for index = 0, 11 do
            if ui.screen:text(index):find("line 29") then
                row = index
            end
        end
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        rows()
        ui:mouse({ kind = "drag", button = "left", row = row, col = 8 })
        rows()
        ui:mouse({ kind = "up", button = "left", row = row, col = 8 })
        emit(rows())
        emit(copied)
        sys.sleep(1.2)
        emit(rows())
        "#,
    )
    .unwrap();
    let before: Vec<&str> = seen[0].split('\n').collect();
    let flashed: Vec<&str> = seen[1].split('\n').collect();
    assert_eq!(seen[2], "line 29");
    assert!(flashed[0].contains("copied 1 line(s)"));
    assert_eq!(
        flashed[1..],
        before[1..],
        "the copy message does not push the transcript up"
    );
    assert_eq!(seen[3], seen[0], "the copy message goes away");
}

#[test]
fn a_selection_stays_on_its_text_when_the_transcript_moves() {
    let seen = screen(
        40,
        24,
        r#"
        local sys = require("uji.sys")
        local copied
        sys.clipboard.set = function(value)
            copied = value
            return true
        end
        for index = 1, 30 do
            app.session:append({ type = "user", text = "line " .. index })
        end
        local function paint()
            ui.screen:clear()
            ui:paint()
        end
        local function find(label)
            for row = 0, 23 do
                if ui.screen:text(row):find(label .. "$") or ui.screen:text(row):find(label .. " ") then
                    return row
                end
            end
        end
        paint()
        local row = find("line 28")
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        paint()
        ui:mouse({ kind = "drag", button = "left", row = row, col = 3 })
        paint()
        app.session:append({ type = "user", text = "line 31" })
        app.session:append({ type = "user", text = "line 32" })
        paint()
        local moved = find("line 28")
        emit(tostring(row - moved))
        ui:mouse({ kind = "drag", button = "left", row = moved, col = 8 })
        paint()
        ui:mouse({ kind = "up", button = "left", row = moved, col = 8 })
        emit(copied)
        copied = nil
        row = find("line 30")
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        paint()
        ui:mouse({ kind = "drag", button = "left", row = row, col = 8 })
        ui.theme.revision = ui.theme.revision + 1
        paint()
        ui:mouse({ kind = "up", button = "left", row = row, col = 8 })
        emit(tostring(copied == nil))
        "#,
    )
    .unwrap();
    assert_ne!(seen[0], "0", "the new messages move the transcript up");
    assert_eq!(
        seen[1], "line 28",
        "the selection follows its text as the transcript moves"
    );
    assert_eq!(
        seen[2], "true",
        "redrawing the whole transcript drops the selection"
    );
}

#[test]
fn new_output_does_not_move_a_transcript_scrolled_up() {
    let seen = screen(
        40,
        16,
        r#"
        for index = 1, 30 do
            app.session:append({ type = "user", text = "old " .. index })
        end
        local function rows()
            ui.screen:clear()
            ui:paint()
            local _, height = ui.screen:size()
            local out = {}
            for row = 0, height - 1 do
                out[#out + 1] = ui.screen:text(row)
            end
            return table.concat(out, "\n")
        end
        emit(rows())
        ui:mouse({ kind = "scroll_up" })
        ui:mouse({ kind = "scroll_up" })
        emit(rows())
        ui.theme.revision = ui.theme.revision + 1
        emit(rows())
        local reply = {}
        for index = 1, 20 do
            reply[index] = "new " .. index
            ui:delta({ text = reply[index] .. "\n\n" })
            ui.stream:reveal_all()
            rows()
        end
        emit(rows())
        ui:clear_stream()
        rows()
        app.session:append({ type = "assistant", text = table.concat(reply, "\n\n") })
        emit(rows())
        local jump = ui.views.messages.jump
        ui:mouse({ kind = "down", button = "left", row = jump.row, col = jump.col })
        emit(rows())
        "#,
    )
    .unwrap();
    let rows: Vec<Vec<&str>> = seen
        .iter()
        .map(|screen| screen.split('\n').map(str::trim_end).collect())
        .collect();
    let at_bottom = &rows[0];
    let scrolled = &rows[1];
    assert!(at_bottom.iter().any(|row| row.contains("old 30")));
    assert!(!at_bottom.iter().any(|row| row.contains("Jump to bottom")));
    assert_ne!(scrolled[0], at_bottom[0]);
    assert!(scrolled.iter().any(|row| row.contains("Jump to bottom")));
    assert_eq!(
        rows[2], *scrolled,
        "redrawing everything keeps the view where it was"
    );
    assert_eq!(
        rows[3], *scrolled,
        "a reply streaming in keeps the view where it was"
    );
    assert_eq!(
        rows[4], *scrolled,
        "the finished reply keeps the view where it was"
    );
    assert!(rows[4].iter().any(|row| row.contains("Jump to bottom")));
    let followed = &rows[5];
    assert!(followed.iter().any(|row| row.contains("new 20")));
    assert!(!followed.iter().any(|row| row.contains("Jump to bottom")));
}
