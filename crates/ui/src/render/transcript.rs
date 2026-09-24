use ratatui::text::Line;
use uji_core::session::conversation::Conversation;
use uji_core::session::model::{Message, StoredMessage};

use crate::app::renderer::Block;
use crate::render::style::Palette;

#[derive(Debug, Default, Clone, Copy)]
struct Grouping {
    started: bool,
    open_group: bool,
}

impl Grouping {
    fn separates(&mut self, stored: &StoredMessage) -> bool {
        let continues = self.open_group && matches!(stored.message, Message::Tool { .. });
        let separates = self.started && !continues;
        self.started = true;
        self.open_group = opens_tool_group(stored);
        separates
    }
}

fn opens_tool_group(stored: &StoredMessage) -> bool {
    match &stored.message {
        Message::Assistant { tool_calls, .. } => !tool_calls.is_empty(),
        Message::Tool { .. } => true,
        _ => false,
    }
}

#[derive(Default)]
struct Streamed {
    key: String,
    settled: usize,
    scanned: usize,
    whole: bool,
    lines: Vec<Line<'static>>,
    open: Vec<Line<'static>>,
}

impl Streamed {
    fn clear(&mut self) {
        self.key.clear();
        self.settled = 0;
        self.scanned = 0;
        self.whole = false;
        self.lines.clear();
        self.open.clear();
    }

    fn scan(&mut self, text: &str) {
        if self.whole {
            return;
        }
        if crate::render::markdown::defines_reference(&text[self.scanned..]) {
            self.whole = true;
            return;
        }
        self.scanned = text.rfind('\n').map_or(0, |at| at.saturating_add(1));
    }

    fn update(
        &mut self,
        text: &str,
        split: bool,
        render: impl Fn(&mut Vec<Line<'static>>, &str, bool),
    ) {
        if self.key == text {
            return;
        }
        if !split || !text.starts_with(self.key.as_str()) {
            self.clear();
        }
        self.scan(text);
        self.key.clear();
        self.key.push_str(text);
        if text.is_empty() {
            return;
        }
        if !split || self.whole {
            self.settled = 0;
            self.lines.clear();
            self.open.clear();
            render(&mut self.open, text, false);
            return;
        }
        let grown = self
            .settled
            .saturating_add(crate::render::markdown::settled(&text[self.settled..]));
        if grown > self.settled {
            let continuing = !self.lines.is_empty();
            render(&mut self.lines, &text[self.settled..grown], continuing);
            self.settled = grown;
        }
        self.open.clear();
        if self.settled < text.len() {
            render(
                &mut self.open,
                &text[self.settled..],
                !self.lines.is_empty(),
            );
        }
    }
}

#[derive(Default)]
struct CachedList {
    key: Vec<String>,
    lines: Vec<Line<'static>>,
}

impl CachedList {
    fn clear(&mut self) {
        self.key.clear();
        self.lines.clear();
    }

    fn get(
        &mut self,
        key: &[String],
        render: impl FnOnce(&mut Vec<Line<'static>>),
    ) -> &[Line<'static>] {
        if self.key != key {
            self.clear();
            self.key.extend_from_slice(key);
            render(&mut self.lines);
        }
        &self.lines
    }
}

pub struct Input<'a> {
    pub conversation: &'a Conversation,
    pub notices: &'a [String],
    pub queued: &'a [String],
    pub thinking: bool,
    pub pending: &'a str,
    pub reasoning: &'a str,
    pub width: usize,
    pub palette: Palette,
}

pub struct Rendered<'a> {
    pub notices: &'a [Line<'static>],
    pub queued: &'a [Line<'static>],
    pub folded: &'a [Line<'static>],
    pub reasoning: &'a [Line<'static>],
    pub reasoning_open: &'a [Line<'static>],
    pub settled: &'a [Line<'static>],
    pub open: &'a [Line<'static>],
}

impl Rendered<'_> {
    pub fn pending_len(&self) -> usize {
        self.live().count()
    }

    pub fn live(&self) -> impl Iterator<Item = &Line<'static>> {
        self.reasoning
            .iter()
            .chain(self.reasoning_open)
            .chain(self.settled)
            .chain(self.open)
    }
}

#[derive(Default)]
pub struct Transcript {
    width: usize,
    thinking: bool,
    palette: Palette,
    folded: usize,
    last_seq: i64,
    grouping: Grouping,
    lines: Vec<Line<'static>>,
    notices: CachedList,
    queued: CachedList,
    pending: Streamed,
    reasoning: Streamed,
}

impl Transcript {
    pub(crate) fn frame(
        &mut self,
        input: &Input<'_>,
        split: bool,
        render: impl Fn(&mut Vec<Line<'static>>, Block<'_>, usize),
    ) -> Rendered<'_> {
        if self.width != input.width
            || self.palette != input.palette
            || self.thinking != input.thinking
        {
            self.width = input.width;
            self.palette = input.palette;
            self.thinking = input.thinking;
            self.reset();
            self.notices.clear();
            self.queued.clear();
            self.pending.clear();
            self.reasoning.clear();
        }
        let width = input.width;
        self.fold(input.conversation, width, input.thinking, &render);
        self.notices.get(input.notices, |lines| {
            for notice in input.notices {
                render(lines, Block::Notice(notice), width);
            }
        });
        self.queued.get(input.queued, |lines| {
            for queued in input.queued {
                render(lines, Block::Queued(queued), width);
            }
        });
        let reasoning = if input.thinking { input.reasoning } else { "" };
        self.reasoning.update(reasoning, split, |lines, chunk, _| {
            render(lines, Block::Thinking(chunk), width);
        });
        self.pending
            .update(input.pending, split, |lines, chunk, continuing| {
                render(
                    lines,
                    Block::Pending {
                        text: chunk,
                        continuing,
                    },
                    width,
                );
            });
        Rendered {
            notices: &self.notices.lines,
            queued: &self.queued.lines,
            folded: &self.lines,
            reasoning: &self.reasoning.lines,
            reasoning_open: &self.reasoning.open,
            settled: &self.pending.lines,
            open: &self.pending.open,
        }
    }

    fn fold(
        &mut self,
        conversation: &Conversation,
        width: usize,
        thinking: bool,
        render: &impl Fn(&mut Vec<Line<'static>>, Block<'_>, usize),
    ) {
        let messages = conversation.messages();
        if !self.continues(messages) {
            self.reset();
        }
        for stored in &messages[self.folded..] {
            self.last_seq = stored.seq;
            if matches!(stored.message, Message::Context { .. }) {
                continue;
            }
            if self.grouping.separates(stored) {
                self.lines.push(Line::from(""));
            }
            if thinking && let Some(reasoning) = stored.message.reasoning() {
                render(&mut self.lines, Block::Thinking(reasoning), width);
            }
            render(&mut self.lines, Block::Message(stored), width);
        }
        self.folded = messages.len();
    }

    fn reset(&mut self) {
        self.folded = 0;
        self.last_seq = 0;
        self.grouping = Grouping::default();
        self.lines.clear();
    }

    fn continues(&self, messages: &[StoredMessage]) -> bool {
        if self.folded > messages.len() {
            return false;
        }
        match self.folded.checked_sub(1) {
            None => true,
            Some(at) => messages[at].seq == self.last_seq,
        }
    }
}
