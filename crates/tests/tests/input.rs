use std::cell::RefCell;
use std::rc::Rc;

use uji_agent::session::conversation::Conversation;
use uji_agent::session::id::SessionId;
use uji_agent::session::model::{Session, Time};
use uji_ui::app::{Action, App, Echo, KeyAction, Mode, SuggestItem};
use uji_ui::keymap::{Binding, Chord, Key, Keymap, Mode as KeyMode, describe};
use uji_ui::state::UiState;

fn app() -> App {
    let session = Session {
        id: SessionId::new(),
        parent_id: None,
        title: String::new(),
        directory: String::from("."),
        time: Time {
            created: 0,
            updated: 0,
        },
    };
    App::new(
        session,
        Conversation::shared(),
        Rc::new(RefCell::new(UiState::new())),
    )
}

fn typing(app: &mut App, text: &str) {
    for c in text.chars() {
        app.handle_key(Chord::plain(Key::Char(c)));
    }
}

fn press(app: &mut App, key: Key) -> KeyAction {
    app.handle_key(Chord::plain(key))
}

fn query(app: &App) -> String {
    match app.mode() {
        Mode::Select { query, .. } | Mode::Pick { query, .. } => query.text().to_string(),
        _ => String::new(),
    }
}

fn matches_len(app: &App) -> usize {
    match app.mode() {
        Mode::Select { matches, .. } | Mode::Pick { matches, .. } => matches.len(),
        _ => 0,
    }
}

fn cursor_at(app: &App) -> usize {
    match app.mode() {
        Mode::Select { cursor, .. } | Mode::Pick { cursor, .. } => *cursor,
        _ => 0,
    }
}

fn action(keymap: &Keymap, mode: KeyMode, spec: &str) -> Option<String> {
    match keymap.get(mode, Chord::parse(spec)?)? {
        Binding::Action(name) => Some(name.clone()),
        Binding::Command(_) | Binding::Unbound => None,
    }
}

#[test]
fn a_leading_bang_runs_a_command_rather_than_sending_it() {
    let mut app = app();
    typing(&mut app, "!cat foo.txt");
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::Shell(String::from("cat foo.txt"))
    );
    assert_eq!(app.input(), "");

    typing(&mut app, "! ");
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::None,
        "a bang with nothing after it runs nothing"
    );
}

#[test]
fn a_slash_is_a_command_and_anything_else_is_a_message() {
    let mut app = app();
    typing(&mut app, "/help");
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::Command(String::from("help"))
    );
    typing(&mut app, "hello");
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::Submit(String::from("hello"))
    );
}

#[test]
fn shift_types_a_capital() {
    let mut app = app();
    app.handle_key(Chord::new(Key::Char('A'), false, false, true));
    app.handle_key(Chord::new(Key::Char('B'), false, false, true));
    typing(&mut app, "c");
    assert_eq!(app.input(), "ABc");
}

#[test]
fn a_modified_key_never_types_its_letter() {
    let mut app = app();
    for chord in [
        Chord::ctrl(Key::Char('w')),
        Chord::alt(Key::Char('d')),
        Chord::ctrl(Key::Char('a')),
    ] {
        assert_eq!(app.handle_key(chord), KeyAction::None);
    }
    assert_eq!(app.input(), "");

    let mut select = self::app();
    select.open_select(String::from("pick"), vec![String::from("one")]);
    typing(&mut select, "ab");
    select.handle_key(Chord::ctrl(Key::Char('w')));
    select.handle_key(Chord::alt(Key::Char('d')));
    assert_eq!(query(&select), "ab");
}

#[test]
fn a_newline_is_composed_and_sent_as_one_message() {
    let mut app = app();
    typing(&mut app, "first");
    app.apply(Action::InsertNewline);
    typing(&mut app, "second");
    assert_eq!(app.input(), "first\nsecond");
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::Submit(String::from("first\nsecond"))
    );

    typing(&mut app, "first \\");
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::None,
        "a trailing backslash continues instead of sending"
    );
    typing(&mut app, "second");
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::Submit(String::from("first \nsecond"))
    );
}

#[test]
fn up_moves_within_a_multi_line_draft_before_it_recalls() {
    let mut app = app();
    typing(&mut app, "first");
    app.apply(Action::InsertNewline);
    typing(&mut app, "second");
    app.apply(Action::HistoryPrev);
    assert_eq!(app.cursor_offset(), 5);
    app.apply(Action::HistoryNext);
    assert_eq!(app.cursor_offset(), 11);
}

#[test]
fn escape_clears_a_draft_and_then_interrupts() {
    let mut app = app();
    typing(&mut app, "half written");
    assert_eq!(press(&mut app, Key::Escape), KeyAction::None);
    assert_eq!(app.input(), "");
    assert_eq!(press(&mut app, Key::Escape), KeyAction::Interrupt);
}

#[test]
fn a_confirm_answers_the_letter_but_not_the_chord() {
    let mut allowing = app();
    allowing.open_confirm(String::from("run?"), String::from("ls"));
    assert_eq!(
        allowing.handle_key(Chord::ctrl(Key::Char('y'))),
        KeyAction::None
    );
    assert_eq!(
        press(&mut allowing, Key::Char('y')),
        KeyAction::Confirmed(true)
    );

    let mut denying = app();
    denying.open_confirm(String::from("run?"), String::from("ls"));
    assert_eq!(
        denying.handle_key(Chord::ctrl(Key::Char('n'))),
        KeyAction::None,
        "<C-n> walks the list"
    );
    assert_eq!(
        press(&mut denying, Key::Char('n')),
        KeyAction::Confirmed(false)
    );
}

#[test]
fn a_prompt_answers_what_was_typed_into_it() {
    let mut app = app();
    app.open_prompt(String::from("key"), String::new(), Echo::Plain);
    typing(&mut app, "ab");
    app.handle_key(Chord::ctrl(Key::Char('y')));
    assert_eq!(
        press(&mut app, Key::Enter),
        KeyAction::Prompted(String::from("ab"))
    );
}

#[test]
fn tab_completes_a_suggestion() {
    let mut app = app();
    app.state().borrow_mut().set_suggest_enabled(true);
    app.set_suggestions(vec![SuggestItem {
        name: String::from("models"),
        desc: String::from("pick the default model"),
    }]);
    typing(&mut app, "/mod");
    assert!(matches!(app.mode(), Mode::Suggest { .. }));
    app.handle_key(Chord::ctrl(Key::Char('w')));
    assert_eq!(
        app.input(),
        "/mod",
        "a chord must not type into the composer"
    );
    press(&mut app, Key::Tab);
    assert_eq!(app.input(), "/models ");
}

#[test]
fn typing_in_a_picker_reranks_it_and_a_page_key_walks_it() {
    let mut app = app();
    app.open_select(
        String::from("pick"),
        vec![String::from("alpha"), String::from("beta")],
    );
    assert_eq!(matches_len(&app), 2);
    typing(&mut app, "alp");
    assert_eq!(matches_len(&app), 1);
    for _ in 0..3 {
        press(&mut app, Key::Backspace);
    }
    assert_eq!(matches_len(&app), 2);

    let items: Vec<String> = (0..30).map(|at| format!("item {at}")).collect();
    let mut long = self::app();
    long.open_select(String::from("pick"), items);
    press(&mut long, Key::PageDown);
    assert!(cursor_at(&long) > 0, "page down should move down the list");
    press(&mut long, Key::PageUp);
    assert_eq!(cursor_at(&long), 0);
}

#[test]
fn the_default_bindings_follow_the_mode() {
    let keymap = Keymap::default();
    assert_eq!(
        action(&keymap, KeyMode::Normal, "<C-w>").as_deref(),
        Some("delete_word_back")
    );
    assert_eq!(
        action(&keymap, KeyMode::Select, "<C-u>").as_deref(),
        Some("delete_to_start")
    );
    assert!(
        action(&keymap, KeyMode::Confirm, "<C-w>").is_none(),
        "there is no text to edit in a confirm"
    );
    assert_eq!(
        action(&keymap, KeyMode::Normal, "<C-p>").as_deref(),
        Some("history_prev")
    );
    assert_eq!(
        action(&keymap, KeyMode::Select, "<C-p>").as_deref(),
        Some("modal_up"),
        "up means the list in a modal"
    );
    for spec in ["<S-CR>", "<A-CR>", "<C-j>"] {
        assert_eq!(
            action(&keymap, KeyMode::Normal, spec).as_deref(),
            Some("insert_newline"),
            "{spec} should insert a newline"
        );
    }
    for mode in [
        KeyMode::Normal,
        KeyMode::Confirm,
        KeyMode::Select,
        KeyMode::Prompt,
        KeyMode::Suggest,
    ] {
        assert_eq!(action(&keymap, mode, "<C-c>").as_deref(), Some("quit"));
    }
}

#[test]
fn a_binding_names_a_key_and_round_trips_through_its_name() {
    let keymap = Keymap::default();
    let upper = Chord::new(Key::Char('W'), true, false, true);
    assert!(matches!(
        keymap.get(KeyMode::Normal, upper),
        Some(Binding::Action(name)) if name == "delete_word_back"
    ));
    for spec in ["<C-w>", "<A-CR>", "<S-CR>", "<C-a>", "x"] {
        let chord = Chord::parse(spec);
        assert!(chord.is_some(), "{spec} should parse");
        let described = chord.map(describe).unwrap_or_default();
        assert_eq!(Chord::parse(&described), chord, "{spec} to {described}");
    }
}
