use serde::{Deserialize, Serialize};
use strum::IntoStaticStr;

use super::id::{MessageId, SessionId};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Time {
    pub created: i64,
    pub updated: i64,
}

pub const UNTITLED: &str = "untitled";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: SessionId,
    pub title: String,
    pub directory: String,
    pub time: Time,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, IntoStaticStr)]
#[serde(tag = "type", rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub enum Message {
    User {
        text: String,
    },
    Assistant {
        text: String,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        tool_calls: Vec<ToolCall>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        reasoning: Option<String>,
    },
    Tool {
        tool_call_id: String,
        name: String,
        content: String,
    },
    System {
        text: String,
    },
    /// A command the user ran from the composer with `!`, and what it printed.
    ///
    /// It is the user's output, not the model's: it is shown in the transcript
    /// and kept with the session, but never sent to the model.
    Shell {
        command: String,
        output: String,
        code: i32,
    },
    Error {
        text: String,
    },
    Compaction {
        summary: String,
        through: i64,
        #[serde(default)]
        files: Vec<String>,
    },
    Context {
        text: String,
    },
}

impl Message {
    pub fn type_name(&self) -> &'static str {
        self.into()
    }

    pub fn text(&self) -> &str {
        match self {
            Message::User { text }
            | Message::Assistant { text, .. }
            | Message::System { text }
            | Message::Error { text }
            | Message::Context { text } => text,
            Message::Tool { content, .. } => content,
            Message::Shell { output, .. } => output,
            Message::Compaction { summary, .. } => summary,
        }
    }

    pub fn reasoning(&self) -> Option<&str> {
        match self {
            Message::Assistant { reasoning, .. } => {
                reasoning.as_deref().filter(|text| !text.is_empty())
            }
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredMessage {
    pub id: MessageId,
    pub seq: i64,
    pub time_created: i64,
    #[serde(flatten)]
    pub message: Message,
}

#[derive(Debug, Clone, Copy)]
pub struct Stamp {
    pub id: MessageId,
    pub seq: i64,
    pub time_created: i64,
}

impl StoredMessage {
    pub fn new(stamp: Stamp, message: Message) -> Self {
        Self {
            id: stamp.id,
            seq: stamp.seq,
            time_created: stamp.time_created,
            message,
        }
    }
}
