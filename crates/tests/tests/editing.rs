use std::error::Error;

use serde_json::Value;
use uji_tests::probe;

const EDITING: &str = r#"
local Composer = require("uji.ui.composer")
local Line = require("uji.ui.line")

local function typed(text)
    local line = Line()
    line:set(text)
    return line
end

local function pasted(count)
    local lines = {}
    for at = 0, count - 1 do
        lines[#lines + 1] = "line " .. at
    end
    return table.concat(lines, "\n")
end
"#;

fn run(lua: &str) -> Result<Vec<Value>, Box<dyn Error>> {
    probe(&format!("{EDITING}\n{lua}"))
}

fn pasted(lines: usize) -> String {
    (0..lines)
        .map(|at| format!("line {at}"))
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn a_word_is_deleted_one_word_at_a_time() {
    let seen = run(r#"
        local line = typed("cargo run --release")
        line:delete_word_back()
        emit(line.text)
        line:delete_word_back()
        emit(line.text)
        local path = typed("open crates/ui/src")
        path:delete_word_back()
        emit(path.text)
    "#)
    .unwrap();
    assert_eq!(seen[0], "cargo run ");
    assert_eq!(seen[1], "cargo ");
    assert_eq!(seen[2], "open ", "a path is one word");
}

#[test]
fn word_motions_stop_where_a_word_starts() {
    let seen = run(r#"
        local line = typed("one two_three four")
        line:home()
        line:word_right()
        emit(line.cursor)
        line:word_right()
        emit(line.cursor)
        line:word_left()
        emit(line.cursor)
        local punctuated = typed("one ... two")
        punctuated:word_left()
        emit(punctuated.cursor)
        punctuated:word_left()
        emit(punctuated.cursor)
    "#)
    .unwrap();
    assert_eq!(seen[0], 3);
    assert_eq!(seen[1], 13, "an underscore joins a word");
    assert_eq!(seen[2], 4);
    assert_eq!(seen[3], 8, "separators are skipped first");
    assert_eq!(seen[4], 0);
}

#[test]
fn a_kill_can_be_yanked_back() {
    let seen = run(r#"
        local line = typed("hello world")
        line:home()
        for _ = 1, 5 do
            line:right()
        end
        line:delete_to_start()
        emit(line.text)
        line:tail()
        line:yank()
        emit(line.text)
    "#)
    .unwrap();
    assert_eq!(seen[0], " world");
    assert_eq!(seen[1], " worldhello");
}

#[test]
fn a_kill_to_the_end_stops_at_the_newline() {
    let seen = run(r#"
        local line = typed("first\nsecond")
        line:home()
        line:up()
        line:right()
        line:right()
        line:delete_to_end()
        emit(line.text)
    "#)
    .unwrap();
    assert_eq!(seen[0], "fi\nsecond");
}

#[test]
fn a_multi_line_draft_moves_by_line_and_keeps_its_column() {
    let seen = run(r#"
        local line = typed("abcd\nefgh")
        line:home()
        line:right()
        line:right()
        emit(line.cursor)
        emit(line:up())
        emit(line.cursor)
        emit(line:down())
        emit(line.cursor)
        local shorter = typed("ab\nlonger")
        emit(shorter:up())
        emit(shorter.cursor)
        local single = typed("only one line")
        emit(single:up())
        emit(single:down())
    "#)
    .unwrap();
    assert_eq!(seen[0], 7, "column 2 of the second line");
    assert!(seen[1] == true);
    assert_eq!(seen[2], 2);
    assert!(seen[3] == true);
    assert_eq!(seen[4], 7);
    assert!(seen[5] == true);
    assert_eq!(seen[6], 2, "clamped to the shorter line");
    assert!(seen[7] != true);
    assert!(seen[8] != true);
}

#[test]
fn home_and_end_stay_on_the_line_the_cursor_is_on() {
    let seen = run(r#"
        local line = typed("first\nsecond")
        line:home()
        emit(line.cursor)
        line:tail()
        emit(line.cursor)
    "#)
    .unwrap();
    assert_eq!(seen[0], 6);
    assert_eq!(seen[1], 12);
}

#[test]
fn editing_stays_on_character_boundaries() {
    let seen = run(r#"
        local line = typed("héllo wörld")
        line:delete_word_back()
        emit(line.text)
        line:backspace()
        emit(line.text)
        line:left()
        line:left()
        line:left()
        line:backspace()
        emit(line.text)
    "#)
    .unwrap();
    assert_eq!(seen[0], "héllo ");
    assert_eq!(seen[1], "héllo");
    assert_eq!(seen[2], "hllo");
}

#[test]
fn moving_the_cursor_does_not_count_as_an_edit() {
    let seen = run(r#"
        local line = typed("text")
        line:home()
        local revision = line.revision
        line:right()
        line:word_right()
        line:tail()
        emit(line.revision)
        emit(revision)
        line:insert("!")
        emit(line.revision)
    "#)
    .unwrap();
    let revision = &seen[1];
    assert_eq!(&seen[0], revision);
    assert_ne!(&seen[2], revision);
}

#[test]
fn a_paste_is_one_marker_that_expands_when_it_is_sent() {
    let seen = run(r"
        local composer = Composer()
        composer:paste(pasted(5))
        emit(composer:text())
        emit(composer:take())
    ")
    .unwrap();
    assert!(seen[0].as_str().unwrap().starts_with("[paste #1"));
    assert_eq!(seen[1], pasted(5));
}

#[test]
fn backspace_takes_a_whole_paste_marker() {
    let seen = run(r"
        local composer = Composer()
        composer:paste(pasted(5))
        composer:backspace()
        emit(composer:text())
    ")
    .unwrap();
    assert_eq!(seen[0], "");
}

#[test]
fn a_half_deleted_paste_marker_does_not_expand() {
    let seen = run(r#"
        local composer = Composer()
        composer:edit(function(line)
            line:insert("x")
        end)
        composer:paste(pasted(5))
        composer:edit(Line.delete_word_back)
        emit(composer:take())
    "#)
    .unwrap();
    assert!(
        !seen[0].as_str().unwrap().contains("line 0"),
        "expanded a marker that was partly deleted"
    );
}

#[test]
fn a_trailing_backslash_continues_the_line() {
    let seen = run(r#"
        local composer = Composer()
        composer:set("first \\")
        emit(composer:continue_line())
        emit(composer:text())
        emit(composer:continue_line())
    "#)
    .unwrap();
    assert!(seen[0] == true);
    assert_eq!(seen[1], "first \n");
    assert!(seen[2] != true);
}

#[test]
fn history_recall_comes_back_to_the_draft() {
    let seen = run(r#"
        local composer = Composer()
        composer:set("draft")
        local history = { [0] = "newest", [1] = "older" }
        local function lookup(back)
            return history[back]
        end
        emit(composer:recall_prev(lookup))
        emit(composer:text())
        emit(composer:recall_prev(lookup))
        emit(composer:text())
        emit(composer:recall_next(lookup))
        emit(composer:recall_next(lookup))
        emit(composer:text())
    "#)
    .unwrap();
    assert!(seen[0] == true);
    assert_eq!(seen[1], "newest");
    assert!(seen[2] == true);
    assert_eq!(seen[3], "older");
    assert!(seen[4] == true);
    assert!(seen[5] == true);
    assert_eq!(seen[6], "draft");
}
