use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;

use crate::llm::Usage;

use super::id::SessionId;
use super::model::{Message, Session, StoredMessage, ToolCall, UNTITLED};

pub type Shared = Rc<RefCell<Conversation>>;

const PLACEHOLDERS: &[&str] = &["", UNTITLED, "new", "resumed"];

#[derive(Default)]
pub struct Info {
    pub id: SessionId,
    pub title: String,
    pub directory: String,
}

impl Info {
    pub fn is_untitled(&self) -> bool {
        PLACEHOLDERS.contains(&self.title.trim())
    }
}

impl From<&Session> for Info {
    fn from(session: &Session) -> Self {
        Self {
            id: session.id,
            title: session.title.clone(),
            directory: session.directory.clone(),
        }
    }
}

#[derive(Default, Clone, Copy)]
pub struct Tally {
    pub usage: Usage,
    pub last: Usage,
    pub turns: u64,
}

#[derive(Default)]
pub struct Conversation {
    info: Info,
    messages: Vec<StoredMessage>,
    tally: Tally,
    reported_input: u64,
    reported_seq: i64,
}

impl Conversation {
    pub fn shared() -> Shared {
        Rc::new(RefCell::new(Self::default()))
    }

    pub fn attach(&mut self, session: &Session, messages: Vec<StoredMessage>) {
        self.info = Info::from(session);
        self.messages = messages;
        self.forget_reported_input();
    }

    pub fn info(&self) -> &Info {
        &self.info
    }

    pub fn set_title(&mut self, title: String) {
        self.info.title = title;
    }

    pub fn messages(&self) -> &[StoredMessage] {
        &self.messages
    }

    pub fn unanswered_calls(&self) -> Vec<&ToolCall> {
        let mut answered = HashSet::new();
        for entry in self.messages.iter().rev() {
            match &entry.message {
                Message::Tool { tool_call_id, .. } => {
                    answered.insert(tool_call_id.as_str());
                }
                Message::Assistant { tool_calls, .. } => {
                    return tool_calls
                        .iter()
                        .filter(|call| !answered.contains(call.id.as_str()))
                        .collect();
                }
                _ => break,
            }
        }
        Vec::new()
    }

    pub fn push(&mut self, message: StoredMessage) {
        if matches!(message.message, Message::Compaction { .. }) {
            self.forget_reported_input();
        }
        self.messages.push(message);
    }

    pub fn reported_input(&self) -> Option<(u64, i64)> {
        (self.reported_input > 0).then_some((self.reported_input, self.reported_seq))
    }

    fn forget_reported_input(&mut self) {
        self.reported_input = 0;
        self.reported_seq = 0;
    }

    pub fn add_cost(&mut self, usage: Usage) {
        self.tally.usage.add(usage);
    }

    pub fn add_usage(&mut self, usage: Usage) {
        if usage.prefix() > 0 {
            self.reported_input = usage.prefix();
            self.reported_seq = self.messages.last().map_or(0, |stored| stored.seq);
        }
        self.tally.last = usage;
        self.tally.usage.add(usage);
        self.tally.turns = self.tally.turns.saturating_add(1);
    }

    pub fn used_tokens(&self) -> u64 {
        match self.reported_input() {
            Some((reported, seq)) => {
                reported.saturating_add(crate::llm::context::estimate_after(&self.messages, seq))
            }
            None => crate::llm::context::estimate_tokens(&self.messages),
        }
    }

    pub fn tally(&self) -> Tally {
        self.tally
    }
}
