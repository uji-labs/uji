use std::cell::RefCell;
use std::io::{self, Stdout};
use std::rc::Rc;

use crossterm::{
    event::{KeyCode, KeyEvent, KeyModifiers},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{Terminal, backend::CrosstermBackend};
use uji_api::state::UiState;

use crate::session::model::{Session, StoredMessage};
use crate::ui;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyAction {
    None,
    Quit,
    Submit(String),
    Command(String),
    Selected(String),
    Prompted(String),
    Cancel,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SuggestItem {
    pub name: String,
    pub desc: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mode {
    Normal,
    Select {
        title: String,
        items: Vec<String>,
        cursor: usize,
    },
    Prompt {
        title: String,
        value: String,
        secret: bool,
    },
    Suggest {
        items: Vec<SuggestItem>,
        cursor: usize,
    },
}

pub struct App {
    session: Session,
    messages: Vec<StoredMessage>,
    state: Rc<RefCell<UiState>>,
    input: String,
    cursor: usize,
    running: bool,
    pending: Option<String>,
    mode: Mode,
    suggest_pool: Vec<SuggestItem>,
}

impl App {
    pub fn new(
        session: Session,
        messages: Vec<StoredMessage>,
        state: Rc<RefCell<UiState>>,
    ) -> Self {
        Self {
            session,
            messages,
            state,
            input: String::new(),
            cursor: 0,
            running: true,
            pending: None,
            mode: Mode::Normal,
            suggest_pool: Vec::new(),
        }
    }

    pub fn session(&self) -> &Session {
        &self.session
    }

    pub fn messages(&self) -> &[StoredMessage] {
        &self.messages
    }

    pub fn push_message(&mut self, message: StoredMessage) {
        self.messages.push(message);
    }

    pub fn state(&self) -> &Rc<RefCell<UiState>> {
        &self.state
    }

    pub fn input(&self) -> &str {
        &self.input
    }

    pub fn cursor_offset(&self) -> usize {
        self.cursor
    }

    pub fn is_running(&self) -> bool {
        self.running
    }

    pub fn pending(&self) -> Option<&str> {
        self.pending.as_deref()
    }

    pub fn append_pending(&mut self, delta: &str) {
        self.pending.get_or_insert_with(String::new).push_str(delta);
    }

    pub fn take_pending(&mut self) -> Option<String> {
        self.pending.take()
    }

    pub fn mode(&self) -> &Mode {
        &self.mode
    }

    pub fn open_select(&mut self, title: String, items: Vec<String>) {
        self.mode = Mode::Select {
            title,
            items,
            cursor: 0,
        };
    }

    pub fn open_prompt(&mut self, title: String, value: String, secret: bool) {
        self.mode = Mode::Prompt {
            title,
            value,
            secret,
        };
    }

    pub fn close_modal(&mut self) {
        self.mode = Mode::Normal;
    }

    pub fn set_suggestions(&mut self, items: Vec<SuggestItem>) {
        self.suggest_pool = items;
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> KeyAction {
        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            return self.quit();
        }
        if matches!(self.mode, Mode::Select { .. }) {
            return self.handle_select_key(key);
        }
        if matches!(self.mode, Mode::Prompt { .. }) {
            return self.handle_prompt_key(key);
        }
        if matches!(self.mode, Mode::Suggest { .. }) {
            return self.handle_suggest_key(key);
        }
        self.handle_normal_key(key)
    }

    fn handle_normal_key(&mut self, key: KeyEvent) -> KeyAction {
        match key.code {
            KeyCode::Esc => self.quit(),
            KeyCode::Char('q') if key.modifiers == KeyModifiers::NONE => self.quit(),
            KeyCode::Char(c) => {
                self.input.insert(self.cursor, c);
                self.cursor += c.len_utf8();
                self.after_input_change();
                KeyAction::None
            }
            KeyCode::Backspace => {
                if self.cursor > 0 {
                    let prev = prev_char_boundary(&self.input, self.cursor);
                    self.input.remove(prev);
                    self.cursor = prev;
                }
                self.after_input_change();
                KeyAction::None
            }
            KeyCode::Left => {
                self.cursor = prev_char_boundary(&self.input, self.cursor);
                KeyAction::None
            }
            KeyCode::Right => {
                self.cursor = next_char_boundary(&self.input, self.cursor);
                KeyAction::None
            }
            KeyCode::Enter => self.take_submit(),
            _ => KeyAction::None,
        }
    }

    fn handle_select_key(&mut self, key: KeyEvent) -> KeyAction {
        match key.code {
            KeyCode::Esc => {
                self.mode = Mode::Normal;
                KeyAction::Cancel
            }
            KeyCode::Up => {
                if let Mode::Select { cursor, .. } = &mut self.mode {
                    *cursor = cursor.saturating_sub(1);
                }
                KeyAction::None
            }
            KeyCode::Down => {
                if let Mode::Select { items, cursor, .. } = &mut self.mode {
                    *cursor = cursor.saturating_add(1).min(items.len().saturating_sub(1));
                }
                KeyAction::None
            }
            KeyCode::Enter => {
                let item = match &self.mode {
                    Mode::Select { items, cursor, .. } => items.get(*cursor).cloned(),
                    _ => None,
                };
                self.mode = Mode::Normal;
                item.map_or(KeyAction::None, KeyAction::Selected)
            }
            _ => KeyAction::None,
        }
    }

    fn handle_prompt_key(&mut self, key: KeyEvent) -> KeyAction {
        match key.code {
            KeyCode::Esc => {
                self.mode = Mode::Normal;
                KeyAction::Cancel
            }
            KeyCode::Enter => {
                let value = match &self.mode {
                    Mode::Prompt { value, .. } => value.clone(),
                    _ => String::new(),
                };
                self.mode = Mode::Normal;
                KeyAction::Prompted(value)
            }
            KeyCode::Backspace => {
                if let Mode::Prompt { value, .. } = &mut self.mode {
                    value.pop();
                }
                KeyAction::None
            }
            KeyCode::Char(c) => {
                if let Mode::Prompt { value, .. } = &mut self.mode {
                    value.push(c);
                }
                KeyAction::None
            }
            _ => KeyAction::None,
        }
    }

    fn handle_suggest_key(&mut self, key: KeyEvent) -> KeyAction {
        match key.code {
            KeyCode::Esc => {
                self.input.clear();
                self.cursor = 0;
                self.mode = Mode::Normal;
                KeyAction::None
            }
            KeyCode::Up => {
                if let Mode::Suggest { cursor, .. } = &mut self.mode {
                    *cursor = cursor.saturating_sub(1);
                }
                KeyAction::None
            }
            KeyCode::Down => {
                if let Mode::Suggest { items, cursor, .. } = &mut self.mode {
                    *cursor = cursor.saturating_add(1).min(items.len().saturating_sub(1));
                }
                KeyAction::None
            }
            KeyCode::Tab => {
                if let Some(name) = self.highlighted_suggest() {
                    self.input = format!("/{name} ");
                    self.cursor = self.input.len();
                    self.mode = Mode::Normal;
                }
                KeyAction::None
            }
            KeyCode::Enter => {
                if let Some(name) = self.highlighted_suggest() {
                    self.input = format!("/{name}");
                    self.cursor = self.input.len();
                }
                self.mode = Mode::Normal;
                self.take_submit()
            }
            KeyCode::Char(c) => {
                self.input.insert(self.cursor, c);
                self.cursor += c.len_utf8();
                self.after_input_change();
                KeyAction::None
            }
            KeyCode::Backspace => {
                if self.cursor > 0 {
                    let prev = prev_char_boundary(&self.input, self.cursor);
                    self.input.remove(prev);
                    self.cursor = prev;
                }
                self.after_input_change();
                KeyAction::None
            }
            _ => KeyAction::None,
        }
    }

    fn highlighted_suggest(&self) -> Option<String> {
        match &self.mode {
            Mode::Suggest { items, cursor } => items.get(*cursor).map(|item| item.name.clone()),
            _ => None,
        }
    }

    fn after_input_change(&mut self) {
        if self.input.starts_with('/')
            && !self.input.contains(' ')
            && self.state.borrow().opts().suggest_enabled
        {
            self.refresh_suggest();
        } else {
            self.mode = Mode::Normal;
        }
    }

    fn refresh_suggest(&mut self) {
        let query = self.input.trim_start_matches('/').to_lowercase();
        let items: Vec<SuggestItem> = self
            .suggest_pool
            .iter()
            .filter(|item| item.name.to_lowercase().starts_with(&query))
            .cloned()
            .collect();
        self.mode = Mode::Suggest { items, cursor: 0 };
    }

    fn quit(&mut self) -> KeyAction {
        self.running = false;
        KeyAction::Quit
    }

    fn take_submit(&mut self) -> KeyAction {
        let text = self.input.trim().to_string();
        self.input.clear();
        self.cursor = 0;
        if text.is_empty() {
            KeyAction::None
        } else if let Some(command) = text.strip_prefix('/') {
            KeyAction::Command(command.to_string())
        } else {
            KeyAction::Submit(text)
        }
    }
}

pub type Term = Terminal<CrosstermBackend<Stdout>>;

pub fn setup() -> io::Result<Term> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    Terminal::new(backend)
}

pub fn restore(terminal: &mut Term) -> io::Result<()> {
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()
}

pub fn draw(terminal: &mut Term, app: &App) -> io::Result<()> {
    terminal.draw(|frame| ui::render(frame, app)).map(|_| ())
}

fn prev_char_boundary(s: &str, index: usize) -> usize {
    if index == 0 {
        return 0;
    }
    let mut i = index - 1;
    while i > 0 && !s.is_char_boundary(i) {
        i -= 1;
    }
    i
}

fn next_char_boundary(s: &str, index: usize) -> usize {
    if index >= s.len() {
        return s.len();
    }
    let mut i = index + 1;
    while i < s.len() && !s.is_char_boundary(i) {
        i += 1;
    }
    i
}
