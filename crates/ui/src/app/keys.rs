use crate::app::line::Line;
use crate::keymap::{Chord, Key};

use crate::model::Builtin;

use super::action::{Action, KeyAction, default_action, rank_items};
use uji_agent::session::conversation::Conversation;
use uji_agent::session::model::Message;

use super::{App, Mode};
use std::rc::Rc;

const SELECT_PAGE: isize = 10;

impl App {
    /// Keys go to the focused window; the modal window then picks the handler
    /// for whatever it is showing.
    pub fn handle_key(&mut self, key: Chord) -> KeyAction {
        if self.focus() == Builtin::Input {
            return self.handle_normal_key(key);
        }
        match self.mode {
            Mode::Select { .. } | Mode::Pick { .. } => self.handle_select_key(key),
            Mode::Prompt { .. } => self.handle_prompt_key(key),
            Mode::Suggest { .. } => self.handle_suggest_key(key),
            Mode::Confirm { .. } => self.handle_confirm_key(key),
            Mode::Normal => self.handle_normal_key(key),
        }
    }

    fn handle_normal_key(&mut self, key: Chord) -> KeyAction {
        match key.key {
            Key::Escape if self.input().is_empty() => KeyAction::Interrupt,
            Key::Escape => self.apply(Action::ClearInput),
            Key::Char(c) if typed(key) => self.insert_char(c),
            Key::Char(_) => KeyAction::None,
            code => match default_action(code) {
                Some(action) => self.apply(action),
                None => KeyAction::None,
            },
        }
    }

    fn handle_select_key(&mut self, key: Chord) -> KeyAction {
        if let Some(action) = modal_key(key.key).or_else(|| list_key(key.key)) {
            return self.apply(action);
        }
        match key.key {
            Key::PageUp => {
                self.select_move(-SELECT_PAGE);
                KeyAction::None
            }
            Key::PageDown => {
                self.select_move(SELECT_PAGE);
                KeyAction::None
            }
            Key::Char(c) if typed(key) => self.insert_char(c),
            Key::Backspace => self.backspace(),
            Key::Left => self.edit_focused(Line::left),
            Key::Right => self.edit_focused(Line::right),
            Key::Home => self.edit_focused(Line::home),
            Key::End => self.edit_focused(Line::end),
            _ => KeyAction::None,
        }
    }

    fn handle_prompt_key(&mut self, key: Chord) -> KeyAction {
        if let Some(action) = modal_key(key.key) {
            return self.apply(action);
        }
        match key.key {
            Key::Backspace => self.backspace(),
            Key::Char(c) if typed(key) => self.insert_char(c),
            Key::Left => self.edit_focused(Line::left),
            Key::Right => self.edit_focused(Line::right),
            Key::Home => self.edit_focused(Line::home),
            Key::End => self.edit_focused(Line::end),
            _ => KeyAction::None,
        }
    }

    fn handle_suggest_key(&mut self, key: Chord) -> KeyAction {
        if let Some(action) = modal_key(key.key).or_else(|| list_key(key.key)) {
            return self.apply(action);
        }
        match key.key {
            Key::Tab => self.apply(Action::SuggestComplete),
            Key::Char(c) if typed(key) => self.insert_char(c),
            Key::Backspace => self.backspace(),
            _ => KeyAction::None,
        }
    }

    fn handle_confirm_key(&mut self, key: Chord) -> KeyAction {
        if let Some(action) = modal_key(key.key).or_else(|| list_key(key.key)) {
            return self.apply(action);
        }
        match key.key {
            Key::Char('y' | 'Y' | '1') if typed(key) => self.apply(Action::ConfirmAllow),
            Key::Char('n' | 'N' | '2') if typed(key) => self.apply(Action::ConfirmDeny),
            Key::Left | Key::Right | Key::Tab => self.apply(Action::ConfirmToggle),
            _ => KeyAction::None,
        }
    }

    pub(super) fn take_submit(&mut self) -> KeyAction {
        if self.composer.continue_line() {
            self.after_input_change();
            return KeyAction::None;
        }
        let text = self.composer.take().trim().to_string();
        if let Some(command) = text.strip_prefix('/') {
            return KeyAction::Command(command.to_string());
        }
        if let Some(command) = text.strip_prefix('!') {
            let command = command.trim().to_string();
            return if command.is_empty() {
                KeyAction::None
            } else {
                KeyAction::Shell(command)
            };
        }
        if text.is_empty() {
            KeyAction::None
        } else {
            KeyAction::Submit(text)
        }
    }

    /// Up walks the message being composed before it reaches for history, the
    /// way a shell does: on a multi-line draft the first press has somewhere
    /// nearer to go.
    pub(super) fn history_prev(&mut self) -> KeyAction {
        if self.composer.up() {
            return KeyAction::None;
        }
        let conversation = Rc::clone(&self.conversation);
        self.composer
            .recall_prev(|back| sent(&conversation.borrow(), back));
        self.after_input_change();
        KeyAction::None
    }

    pub(super) fn history_next(&mut self) -> KeyAction {
        if self.composer.down() {
            return KeyAction::None;
        }
        let conversation = Rc::clone(&self.conversation);
        self.composer
            .recall_next(|back| sent(&conversation.borrow(), back));
        self.after_input_change();
        KeyAction::None
    }

    pub(super) fn clear_input(&mut self) -> KeyAction {
        self.composer.clear();
        self.after_input_change();
        KeyAction::None
    }

    fn insert_char(&mut self, c: char) -> KeyAction {
        self.edit_focused(|line| line.insert(c));
        KeyAction::None
    }

    pub(super) fn backspace(&mut self) -> KeyAction {
        if self.composing() {
            self.composer.backspace();
            self.after_input_change();
            return KeyAction::None;
        }
        self.edit_focused(Line::backspace)
    }

    /// Whether the composer owns the text being edited, rather than a modal.
    fn composing(&self) -> bool {
        matches!(self.mode, Mode::Normal | Mode::Suggest { .. })
    }

    /// Run an edit against whichever line has focus.
    ///
    /// The composer, a prompt's value and a picker's query are all one `Line`,
    /// so every editing action is written once here and works wherever the
    /// cursor happens to be. Only an edit that changed the text reranks the
    /// picker or re-reads the composer for a command prefix.
    pub(super) fn edit_focused(&mut self, change: impl FnOnce(&mut Line)) -> KeyAction {
        enum Touched {
            Nothing,
            Query,
            Input,
        }
        let touched = match &mut self.mode {
            Mode::Prompt { value, .. } => {
                change(value);
                Touched::Nothing
            }
            Mode::Select { query, cursor, .. } | Mode::Pick { query, cursor, .. } => {
                let before = query.revision();
                change(query);
                if query.revision() == before {
                    Touched::Nothing
                } else {
                    *cursor = 0;
                    Touched::Query
                }
            }
            Mode::Normal | Mode::Suggest { .. } => {
                let before = self.composer.revision();
                self.composer.edit(change);
                if self.composer.revision() == before {
                    Touched::Nothing
                } else {
                    Touched::Input
                }
            }
            Mode::Confirm { .. } => Touched::Nothing,
        };
        match touched {
            Touched::Query => self.rerank(),
            Touched::Input => self.after_input_change(),
            Touched::Nothing => {}
        }
        KeyAction::None
    }

    pub(super) fn line_up(&mut self) -> KeyAction {
        self.scroll_up(1);
        KeyAction::None
    }

    pub(super) fn line_down(&mut self) -> KeyAction {
        self.scroll_down(1);
        KeyAction::None
    }

    pub(super) fn page_up(&mut self) -> KeyAction {
        self.scroll_up(self.viewport().max(1));
        KeyAction::None
    }

    pub(super) fn page_down(&mut self) -> KeyAction {
        self.scroll_down(self.viewport().max(1));
        KeyAction::None
    }

    pub(super) fn top(&mut self) -> KeyAction {
        self.jump_top();
        KeyAction::None
    }

    pub(super) fn bottom(&mut self) -> KeyAction {
        self.jump_bottom();
        KeyAction::None
    }

    pub(super) fn modal_up(&mut self) -> KeyAction {
        self.modal_move(-1);
        KeyAction::None
    }

    pub(super) fn modal_down(&mut self) -> KeyAction {
        self.modal_move(1);
        KeyAction::None
    }

    pub(super) fn modal_accept(&mut self) -> KeyAction {
        match &self.mode {
            Mode::Select { cursor, .. } | Mode::Pick { cursor, .. } => {
                let cursor = *cursor;
                let item = self
                    .select_matches()
                    .get(cursor)
                    .map(|item| (*item).clone());
                self.mode = Mode::Normal;
                item.map_or(KeyAction::None, KeyAction::Selected)
            }
            Mode::Prompt { value, .. } => {
                let value = value.text().to_string();
                self.mode = Mode::Normal;
                KeyAction::Prompted(value)
            }
            Mode::Suggest { .. } => {
                if let Some(name) = self.highlighted_suggest() {
                    self.composer.set(format!("/{name}"));
                }
                self.mode = Mode::Normal;
                self.take_submit()
            }
            Mode::Confirm { allow, .. } => {
                let allow = *allow;
                self.mode = Mode::Normal;
                KeyAction::Confirmed(allow)
            }
            Mode::Normal => self.take_submit(),
        }
    }

    pub(super) fn modal_cancel(&mut self) -> KeyAction {
        match self.mode {
            Mode::Suggest { .. } => {
                self.composer.clear();
                self.mode = Mode::Normal;
                KeyAction::None
            }
            Mode::Confirm { .. } => KeyAction::Confirmed(false),
            Mode::Normal => KeyAction::InterruptOrQuit,
            _ => {
                self.mode = Mode::Normal;
                KeyAction::Cancel
            }
        }
    }

    pub(super) fn suggest_complete(&mut self) -> KeyAction {
        if let Some(name) = self.highlighted_suggest() {
            self.composer.set(format!("/{name} "));
            self.mode = Mode::Normal;
        }
        KeyAction::None
    }

    pub(super) fn confirm_allow(&mut self) -> KeyAction {
        self.mode = Mode::Normal;
        KeyAction::Confirmed(true)
    }

    pub(super) fn confirm_deny(&mut self) -> KeyAction {
        self.mode = Mode::Normal;
        KeyAction::Confirmed(false)
    }

    pub(super) fn confirm_toggle(&mut self) -> KeyAction {
        if let Mode::Confirm { allow, .. } = &mut self.mode {
            *allow = !*allow;
        }
        KeyAction::None
    }

    fn modal_move(&mut self, delta: isize) {
        match &mut self.mode {
            Mode::Select { .. } | Mode::Pick { .. } => self.select_move(delta),
            Mode::Suggest { items, cursor } => {
                *cursor = step(*cursor, delta, items.len());
            }
            Mode::Confirm { allow, .. } => *allow = delta < 0,
            Mode::Normal | Mode::Prompt { .. } => {}
        }
    }

    pub(super) fn rerank(&mut self) {
        let (Mode::Select {
            items,
            query,
            matches,
            ..
        }
        | Mode::Pick {
            items,
            query,
            matches,
            ..
        }) = &mut self.mode
        else {
            return;
        };
        *matches = rank_items(items, query.text());
    }

    fn select_matches(&self) -> Vec<&String> {
        match &self.mode {
            Mode::Select { items, matches, .. } | Mode::Pick { items, matches, .. } => {
                matches.iter().filter_map(|at| items.get(*at)).collect()
            }
            _ => Vec::new(),
        }
    }

    fn select_move(&mut self, delta: isize) {
        let len = self.select_matches().len();
        if let Mode::Select { cursor, .. } | Mode::Pick { cursor, .. } = &mut self.mode {
            *cursor = step(*cursor, delta, len);
        }
    }

    fn highlighted_suggest(&self) -> Option<String> {
        match &self.mode {
            Mode::Suggest { items, cursor } => items.get(*cursor).map(|item| item.name.clone()),
            _ => None,
        }
    }
}

/// Move a modal cursor. Single steps cycle the list the way telescope does;
/// page jumps clamp, so paging never teleports across the ends.
fn step(cursor: usize, delta: isize, len: usize) -> usize {
    if len == 0 {
        return 0;
    }
    let last = len.saturating_sub(1);
    let distance = delta.unsigned_abs();
    match (distance, delta < 0) {
        (1, true) if cursor == 0 => last,
        (1, false) if cursor >= last => 0,
        (_, true) => cursor.saturating_sub(distance),
        (_, false) => cursor.saturating_add(distance).min(last),
    }
}

/// Whether a chord is someone typing a character, rather than reaching for a
/// binding. Without this every unbound `<C-w>` would type a `w`.
fn typed(chord: Chord) -> bool {
    !chord.ctrl && !chord.alt
}

/// Keys every modal answers the same way.
fn modal_key(code: Key) -> Option<Action> {
    match code {
        Key::Escape => Some(Action::ModalCancel),
        Key::Enter => Some(Action::ModalAccept),
        _ => None,
    }
}

/// Navigation shared by the modals that show a list.
fn list_key(code: Key) -> Option<Action> {
    match code {
        Key::Up => Some(Action::ModalUp),
        Key::Down => Some(Action::ModalDown),
        _ => None,
    }
}

fn sent(conversation: &Conversation, back: usize) -> Option<String> {
    conversation
        .messages()
        .iter()
        .rev()
        .filter_map(|stored| match &stored.message {
            Message::User { text } => Some(text),
            _ => None,
        })
        .nth(back)
        .cloned()
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::rc::Rc;

    use uji_agent::session::conversation::Conversation;
    use uji_agent::session::id::SessionId;
    use uji_agent::session::model::{Session, Time};

    use crate::app::{Action, App, KeyAction, Mode};
    use crate::keymap::{Chord, Key};
    use crate::state::UiState;

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

    fn enter(app: &mut App) -> KeyAction {
        app.handle_key(Chord::plain(Key::Enter))
    }

    #[test]
    fn a_leading_bang_runs_a_command_instead_of_sending_it() {
        let mut app = app();
        typing(&mut app, "!cat foo.txt");
        assert_eq!(
            enter(&mut app),
            KeyAction::Shell(String::from("cat foo.txt"))
        );
        assert_eq!(app.input(), "");
    }

    #[test]
    fn a_bare_bang_sends_nothing() {
        let mut app = app();
        typing(&mut app, "! ");
        assert_eq!(enter(&mut app), KeyAction::None);
    }

    #[test]
    fn a_slash_is_still_a_command_and_plain_text_is_still_a_message() {
        let mut app = app();
        typing(&mut app, "/help");
        assert_eq!(enter(&mut app), KeyAction::Command(String::from("help")));
        typing(&mut app, "hello");
        assert_eq!(enter(&mut app), KeyAction::Submit(String::from("hello")));
    }

    /// The bug that made `<C-w>` type a `w`: a chord is not a character.
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
    }

    #[test]
    fn a_newline_is_composed_not_sent() {
        let mut app = app();
        typing(&mut app, "first");
        app.apply(Action::InsertNewline);
        typing(&mut app, "second");
        assert_eq!(app.input(), "first\nsecond");
        assert_eq!(
            enter(&mut app),
            KeyAction::Submit(String::from("first\nsecond"))
        );
    }

    #[test]
    fn a_trailing_backslash_composes_instead_of_sending() {
        let mut app = app();
        typing(&mut app, "first \\");
        assert_eq!(enter(&mut app), KeyAction::None);
        typing(&mut app, "second");
        assert_eq!(
            enter(&mut app),
            KeyAction::Submit(String::from("first \nsecond"))
        );
    }

    /// Up walks the draft first, and only then reaches for history.
    #[test]
    fn up_moves_within_a_multi_line_draft() {
        let mut app = app();
        typing(&mut app, "first");
        app.apply(Action::InsertNewline);
        typing(&mut app, "second");
        app.apply(Action::HistoryPrev);
        assert_eq!(app.cursor_offset(), 5);
        // Column 5 of the second line: the column is kept, not the offset.
        app.apply(Action::HistoryNext);
        assert_eq!(app.cursor_offset(), 11);
    }

    #[test]
    fn readline_edits_reach_a_modal_query() {
        let mut app = app();
        app.open_select(String::from("pick"), vec![String::from("one")]);
        typing(&mut app, "abc def");
        app.apply(Action::DeleteWordBack);
        let query = match app.mode() {
            Mode::Select { query, .. } => query.text(),
            _ => "",
        };
        assert_eq!(query, "abc ");
    }

    #[test]
    fn readline_edits_reach_a_prompt() {
        let mut app = app();
        app.open_prompt(String::from("key"), String::new(), crate::app::Echo::Plain);
        typing(&mut app, "secret value");
        app.apply(Action::CursorStart);
        app.apply(Action::DeleteToEnd);
        assert_eq!(
            app.handle_key(Chord::plain(Key::Enter)),
            KeyAction::Prompted(String::new())
        );
    }
}
