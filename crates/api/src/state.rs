use std::time::Instant;

use crate::model::{GlobalOpts, RunState, UiModel, WaitingOpts, WinOpts, WindowKind, WindowSpec};

#[derive(Debug, Default)]
pub struct UiState {
    windows: Vec<WindowSpec>,
    opts: GlobalOpts,
    current_provider: Option<String>,
    current_model: Option<String>,
    next_window_id: u32,
    run_state: RunState,
    turn_started: Option<Instant>,
    footer: Vec<String>,
}

impl UiState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push_window(&mut self, kind: WindowKind, lines: Vec<String>, opts: WinOpts) -> u32 {
        let id = self.next_window_id;
        self.next_window_id += 1;
        self.windows.push(WindowSpec {
            id,
            kind,
            lines,
            opts,
        });
        id
    }

    pub fn close_window(&mut self, id: u32) -> bool {
        let before = self.windows.len();
        self.windows.retain(|w| w.id != id);
        self.windows.len() != before
    }

    pub fn clear(&mut self) {
        self.windows.clear();
    }

    pub fn windows(&self) -> &[WindowSpec] {
        &self.windows
    }

    pub fn opts(&self) -> GlobalOpts {
        self.opts.clone()
    }

    pub fn set_cursor_blink(&mut self, on: bool) {
        self.opts.cursor_blink = on;
    }

    pub fn set_suggest_enabled(&mut self, enabled: bool) {
        self.opts.suggest_enabled = enabled;
    }

    pub fn set_suggest_max_height(&mut self, max_height: u16) {
        self.opts.suggest_max_height = max_height;
    }

    pub fn set_waiting(&mut self, waiting: WaitingOpts) {
        self.opts.waiting = waiting;
    }

    pub fn push_footer(&mut self, segment: String) {
        self.footer.push(segment);
    }

    pub fn clear_footer(&mut self) {
        self.footer.clear();
    }

    pub fn loader_frames(&self) -> &[String] {
        &self.opts.waiting.loader_frames
    }

    pub fn loader_interval_ms(&self) -> u64 {
        self.opts.waiting.loader_interval_ms
    }

    pub fn current_provider(&self) -> Option<&str> {
        self.current_provider.as_deref()
    }

    pub fn current_model(&self) -> Option<&str> {
        self.current_model.as_deref()
    }

    pub fn set_current_provider(&mut self, provider: String) {
        self.current_provider = Some(provider);
    }

    pub fn set_current_model(&mut self, model: String) {
        self.current_model = Some(model);
    }

    pub fn run_state(&self) -> RunState {
        self.run_state
    }

    pub fn set_run_state(&mut self, state: RunState) {
        self.run_state = state;
    }

    pub fn turn_started(&self) -> Option<Instant> {
        self.turn_started
    }

    pub fn set_turn_started(&mut self, started: Option<Instant>) {
        self.turn_started = started;
    }

    pub fn footer(&self) -> &[String] {
        &self.footer
    }

    pub fn set_footer(&mut self, footer: Vec<String>) {
        self.footer = footer;
    }

    pub fn loader_frame(&self) -> String {
        let Some(started) = self.turn_started else {
            return String::new();
        };
        let frames = &self.opts.waiting.loader_frames;
        if frames.is_empty() {
            return String::new();
        }
        let interval = u128::from(self.opts.waiting.loader_interval_ms.max(1));
        let len = u128::try_from(frames.len()).unwrap_or(1);
        let idx = (started.elapsed().as_millis() / interval) % len;
        let idx = usize::try_from(idx).unwrap_or(0);
        frames[idx].clone()
    }

    pub fn snapshot(&self) -> UiModel {
        UiModel {
            windows: self.windows.clone(),
            opts: self.opts.clone(),
        }
    }
}
