use std::cell::RefCell;
use std::io::{self, Stdout};
use std::rc::Rc;

use crossterm::{
    event::{KeyCode, KeyEvent, KeyModifiers},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{Terminal, backend::CrosstermBackend};
use uji_core::session::model::{Session, StoredMessage};

use crate::state::UiState;
use crate::ui;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyAction {
    None,
    Quit,
    Submit(String),
}

pub struct App {
    session: Session,
    messages: Vec<StoredMessage>,
    state: Rc<RefCell<UiState>>,
    input: String,
    cursor: usize,
    running: bool,
    pending: Option<String>,
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

    pub fn pending(&self) -> Option<&str> {
        self.pending.as_deref()
    }

    pub fn append_pending(&mut self, delta: &str) {
        self.pending.get_or_insert_with(String::new).push_str(delta);
    }

    pub fn take_pending(&mut self) -> Option<String> {
        self.pending.take()
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

    pub fn handle_key(&mut self, key: KeyEvent) -> KeyAction {
        match key.code {
            KeyCode::Esc => self.quit(),
            KeyCode::Char('c') if key.modifiers == KeyModifiers::CONTROL => self.quit(),
            KeyCode::Char('q') if key.modifiers == KeyModifiers::NONE => self.quit(),
            KeyCode::Char(c) => {
                self.input.insert(self.cursor, c);
                self.cursor += c.len_utf8();
                KeyAction::None
            }
            KeyCode::Backspace => {
                if self.cursor > 0 {
                    let prev = prev_char_boundary(&self.input, self.cursor);
                    self.input.remove(prev);
                    self.cursor = prev;
                }
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
