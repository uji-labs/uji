pub mod action;
pub mod composer;
pub mod keys;
pub mod line;
pub mod mode;
pub mod overlay;
pub mod paste;
pub mod renderer;
pub mod scroll;
pub mod selection;
pub mod stream;

pub use action::{Action, KeyAction, rank_items};
pub use composer::Composer;
pub use line::Line;
pub use mode::{Echo, Mode, SuggestItem};
pub use scroll::Scroll;
pub use stream::Stream;

use std::cell::{Ref, RefCell, RefMut};
use std::rc::Rc;

use crate::keymap;
use crate::state::UiState;

use uji_agent::session::conversation::{Conversation, Shared};
use uji_agent::session::model::Session;

pub struct App {
    session: Session,
    conversation: Shared,
    state: Rc<RefCell<UiState>>,
    composer: Composer,
    stream: Stream,
    scroll: Scroll,
    mode: Mode,
    suggest_pool: Vec<SuggestItem>,
    overlay: overlay::Overlay,
    transcript: RefCell<crate::render::transcript::Transcript>,
    typed: RefCell<crate::render::input::Layout>,
    renderer: Option<Rc<dyn renderer::BlockRenderer>>,
}

impl App {
    pub fn new(session: Session, conversation: Shared, state: Rc<RefCell<UiState>>) -> Self {
        Self {
            session,
            conversation,
            state,
            composer: Composer::default(),
            stream: Stream::default(),
            scroll: Scroll::default(),
            mode: Mode::Normal,
            suggest_pool: Vec::new(),
            overlay: overlay::Overlay::default(),
            transcript: RefCell::default(),
            typed: RefCell::default(),
            renderer: None,
        }
    }

    pub fn session(&self) -> &Session {
        &self.session
    }

    pub fn set_title(&mut self, title: String) {
        self.session.title = title;
    }

    pub fn conversation(&self) -> &Shared {
        &self.conversation
    }

    pub fn messages(&self) -> Ref<'_, Conversation> {
        self.conversation.borrow()
    }

    pub fn transcript(&self) -> RefMut<'_, crate::render::transcript::Transcript> {
        self.transcript.borrow_mut()
    }

    pub fn typed(&self) -> RefMut<'_, crate::render::input::Layout> {
        self.typed.borrow_mut()
    }

    pub fn input_revision(&self) -> u64 {
        self.composer.revision()
    }

    pub fn set_renderer(&mut self, renderer: Rc<dyn renderer::BlockRenderer>) {
        self.renderer = Some(renderer);
    }

    pub fn renderer(&self) -> Option<&Rc<dyn renderer::BlockRenderer>> {
        self.renderer.as_ref()
    }

    pub fn state(&self) -> &Rc<RefCell<UiState>> {
        &self.state
    }

    pub fn input(&self) -> &str {
        self.composer.text()
    }

    pub fn cursor_offset(&self) -> usize {
        self.composer.cursor()
    }

    pub fn toggle_thinking(&mut self) -> KeyAction {
        let shown = self.state.borrow_mut().toggle_thinking();
        self.overlay_mut().push_notices(vec![String::from(if shown {
            "thinking: shown"
        } else {
            "thinking: hidden"
        })]);
        KeyAction::None
    }

    pub fn paste(&mut self, text: &str) {
        match &mut self.mode {
            Mode::Prompt { value, .. } => {
                value.insert_str(&paste::single_line(text));
                return;
            }
            Mode::Select { query, cursor, .. } | Mode::Pick { query, cursor, .. } => {
                query.insert_str(&paste::single_line(text));
                *cursor = 0;
            }
            Mode::Confirm { .. } => return,
            Mode::Normal | Mode::Suggest { .. } => {
                self.composer.paste(text);
                self.after_input_change();
                return;
            }
        }
        self.rerank();
    }

    pub fn set_input(&mut self, text: String) {
        self.composer.set(text);
        self.after_input_change();
    }

    pub fn pending(&self) -> Option<&str> {
        Some(self.stream.visible()).filter(|text| !text.is_empty())
    }

    pub fn append_pending(&mut self, delta: &str) {
        self.stream.push(delta);
    }

    pub fn take_pending(&mut self) {
        self.stream.clear();
    }

    pub fn revealing(&self) -> bool {
        self.stream.revealing()
    }

    pub fn reveal_all(&mut self) {
        self.stream.reveal_all();
    }

    pub fn reveal_step(&mut self) -> bool {
        self.stream.reveal_step()
    }

    pub fn resolve_scroll(&self, max: usize, viewport: usize) -> usize {
        self.scroll.resolve(max, viewport)
    }

    pub fn viewport(&self) -> usize {
        self.scroll.viewport()
    }

    pub fn reset_scroll(&self) {
        self.scroll.follow();
    }

    pub fn scroll_up(&self, lines: usize) {
        self.scroll.up(lines);
    }

    pub fn scroll_down(&self, lines: usize) {
        self.scroll.down(lines);
    }

    pub fn jump_top(&self) {
        self.scroll.top();
    }

    pub fn jump_bottom(&self) {
        self.scroll.follow();
    }

    pub fn mode(&self) -> &Mode {
        &self.mode
    }

    pub fn overlay(&self) -> &overlay::Overlay {
        &self.overlay
    }

    pub fn overlay_mut(&mut self) -> &mut overlay::Overlay {
        &mut self.overlay
    }

    pub fn open_select(&mut self, title: String, items: Vec<String>) {
        let matches = (0..items.len()).collect();
        self.mode = Mode::Select {
            title,
            items,
            query: Line::default(),
            cursor: 0,
            matches,
        };
    }

    pub fn open_pick(&mut self, title: String, items: Vec<String>, live: bool) {
        let matches = (0..items.len()).collect();
        self.mode = Mode::Pick {
            title,
            items,
            query: Line::default(),
            cursor: 0,
            matches,
            preview: Vec::new(),
            previewed: None,
            live,
        };
    }

    /// Replace a live picker's candidates with a fresh set from Lua.
    pub fn set_pick_items(&mut self, next: Vec<String>) {
        if let Mode::Pick {
            items,
            matches,
            cursor,
            previewed,
            ..
        } = &mut self.mode
        {
            *items = next;
            *matches = (0..items.len()).collect();
            *cursor = 0;
            *previewed = None;
        }
    }

    /// The query of an open live picker, if it has one.
    pub fn live_query(&self) -> Option<&str> {
        match &self.mode {
            Mode::Pick { query, live, .. } if *live => Some(query.text()),
            _ => None,
        }
    }

    /// The item under the cursor, if a picker is open.
    pub fn picked(&self) -> Option<(usize, &str)> {
        let Mode::Pick {
            items,
            matches,
            cursor,
            ..
        } = &self.mode
        else {
            return None;
        };
        let at = *matches.get(*cursor)?;
        Some((*cursor, items.get(at)?.as_str()))
    }

    /// Whether the highlighted item still needs its preview fetched.
    pub fn preview_pending(&self) -> bool {
        matches!(&self.mode, Mode::Pick { cursor, previewed, matches, .. }
            if !matches.is_empty() && *previewed != Some(*cursor))
    }

    pub fn set_preview(&mut self, lines: Vec<String>) {
        if let Mode::Pick {
            preview,
            previewed,
            cursor,
            ..
        } = &mut self.mode
        {
            *preview = lines;
            *previewed = Some(*cursor);
        }
    }

    pub fn open_prompt(&mut self, title: String, value: String, echo: Echo) {
        let mut line = Line::default();
        line.set(value);
        self.mode = Mode::Prompt {
            title,
            value: line,
            echo,
        };
    }

    pub fn open_confirm(&mut self, title: String, body: String) {
        self.mode = Mode::Confirm {
            title,
            body,
            allow: true,
        };
    }

    pub fn close_modal(&mut self) {
        self.mode = Mode::Normal;
    }

    pub fn set_suggestions(&mut self, items: Vec<SuggestItem>) {
        self.suggest_pool = items;
    }

    /// The window that owns keys and the cursor.
    pub fn focus(&self) -> crate::model::Builtin {
        self.mode.focus()
    }

    pub fn keymap_mode(&self) -> keymap::Mode {
        match self.mode {
            Mode::Normal => keymap::Mode::Normal,
            Mode::Select { .. } | Mode::Pick { .. } => keymap::Mode::Select,
            Mode::Prompt { .. } => keymap::Mode::Prompt,
            Mode::Suggest { .. } => keymap::Mode::Suggest,
            Mode::Confirm { .. } => keymap::Mode::Confirm,
        }
    }

    fn after_input_change(&mut self) {
        let input = self.composer.text();
        if input.starts_with('/')
            && !input.contains(' ')
            && self.state.borrow().opts().suggest_enabled
        {
            self.refresh_suggest();
        } else {
            self.mode = Mode::Normal;
        }
    }

    fn refresh_suggest(&mut self) {
        let query = self.composer.text().trim_start_matches('/').to_lowercase();
        let items: Vec<SuggestItem> = self
            .suggest_pool
            .iter()
            .filter(|item| item.name.to_lowercase().starts_with(&query))
            .cloned()
            .collect();
        self.mode = Mode::Suggest { items, cursor: 0 };
    }
}
