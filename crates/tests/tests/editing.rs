use uji_ui::app::{Composer, Line};

fn typed(text: &str) -> Line {
    let mut line = Line::default();
    line.set(String::from(text));
    line
}

fn pasted(lines: usize) -> String {
    (0..lines)
        .map(|at| format!("line {at}"))
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn a_word_is_deleted_one_word_at_a_time() {
    let mut line = typed("cargo run --release");
    line.delete_word_back();
    assert_eq!(line.text(), "cargo run ");
    line.delete_word_back();
    assert_eq!(line.text(), "cargo ");

    let mut path = typed("open crates/ui/src");
    path.delete_word_back();
    assert_eq!(path.text(), "open ", "a path is one word");
}

#[test]
fn word_motions_stop_where_a_word_starts() {
    let mut line = typed("one two_three four");
    line.home();
    line.word_right();
    assert_eq!(line.cursor(), 3);
    line.word_right();
    assert_eq!(line.cursor(), 13, "an underscore joins a word");
    line.word_left();
    assert_eq!(line.cursor(), 4);

    let mut punctuated = typed("one ... two");
    punctuated.word_left();
    assert_eq!(punctuated.cursor(), 8, "separators are skipped first");
    punctuated.word_left();
    assert_eq!(punctuated.cursor(), 0);
}

#[test]
fn a_kill_can_be_yanked_back() {
    let mut line = typed("hello world");
    line.home();
    for _ in 0..5 {
        line.right();
    }
    line.delete_to_start();
    assert_eq!(line.text(), " world");
    line.end();
    line.yank();
    assert_eq!(line.text(), " worldhello");
}

#[test]
fn a_kill_to_the_end_stops_at_the_newline() {
    let mut line = typed("first\nsecond");
    line.home();
    line.up();
    line.right();
    line.right();
    line.delete_to_end();
    assert_eq!(line.text(), "fi\nsecond");
}

#[test]
fn a_multi_line_draft_moves_by_line_and_keeps_its_column() {
    let mut line = typed("abcd\nefgh");
    line.home();
    line.right();
    line.right();
    assert_eq!(line.cursor(), 7, "column 2 of the second line");
    assert!(line.up());
    assert_eq!(line.cursor(), 2);
    assert!(line.down());
    assert_eq!(line.cursor(), 7);

    let mut shorter = typed("ab\nlonger");
    assert!(shorter.up());
    assert_eq!(shorter.cursor(), 2, "clamped to the shorter line");

    let mut single = typed("only one line");
    assert!(!single.up());
    assert!(!single.down());
}

#[test]
fn home_and_end_stay_on_the_line_the_cursor_is_on() {
    let mut line = typed("first\nsecond");
    line.home();
    assert_eq!(line.cursor(), 6);
    line.end();
    assert_eq!(line.cursor(), 12);
}

#[test]
fn editing_stays_on_character_boundaries() {
    let mut line = typed("héllo wörld");
    line.delete_word_back();
    assert_eq!(line.text(), "héllo ");
    line.backspace();
    assert_eq!(line.text(), "héllo");
    line.left();
    line.left();
    line.left();
    line.backspace();
    assert_eq!(line.text(), "hllo");
}

#[test]
fn moving_the_cursor_does_not_count_as_an_edit() {
    let mut line = typed("text");
    line.home();
    let revision = line.revision();
    line.right();
    line.word_right();
    line.end();
    assert_eq!(line.revision(), revision);
    line.insert('!');
    assert_ne!(line.revision(), revision);
}

#[test]
fn a_paste_is_one_marker_that_expands_when_it_is_sent() {
    let mut composer = Composer::default();
    composer.paste(&pasted(5));
    assert!(composer.text().starts_with("[paste #1"));
    assert_eq!(composer.take(), pasted(5));
}

#[test]
fn backspace_takes_a_whole_paste_marker() {
    let mut composer = Composer::default();
    composer.paste(&pasted(5));
    composer.backspace();
    assert_eq!(composer.text(), "");
}

#[test]
fn a_half_deleted_paste_marker_does_not_expand() {
    let mut composer = Composer::default();
    composer.edit(|line| line.insert('x'));
    composer.paste(&pasted(5));
    composer.edit(Line::delete_word_back);
    assert!(
        !composer.take().contains("line 0"),
        "expanded a marker that was partly deleted"
    );
}

#[test]
fn a_trailing_backslash_continues_the_line() {
    let mut composer = Composer::default();
    composer.set(String::from("first \\"));
    assert!(composer.continue_line());
    assert_eq!(composer.text(), "first \n");
    assert!(!composer.continue_line());
}

#[test]
fn history_recall_comes_back_to_the_draft() {
    let mut composer = Composer::default();
    composer.set(String::from("draft"));
    let history = |back: usize| {
        ["newest", "older"]
            .get(back)
            .map(|text| (*text).to_string())
    };
    assert!(composer.recall_prev(history));
    assert_eq!(composer.text(), "newest");
    assert!(composer.recall_prev(history));
    assert_eq!(composer.text(), "older");
    assert!(composer.recall_next(history));
    assert!(composer.recall_next(history));
    assert_eq!(composer.text(), "draft");
}
