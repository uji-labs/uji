use serde::{Deserialize, Serialize};

use super::id::{MessageId, SessionId};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Time {
    pub created: i64,
    pub updated: i64,
}

pub const UNTITLED: &str = "untitled";

const PLACEHOLDERS: &[&str] = &["", UNTITLED, "new", "resumed"];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: SessionId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<SessionId>,
    pub title: String,
    pub directory: String,
    pub time: Time,
}

impl Session {
    pub fn is_untitled(&self) -> bool {
        let title = self.title.trim();
        PLACEHOLDERS.contains(&title)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum Message {
    #[serde(rename = "user")]
    User { text: String },
    #[serde(rename = "assistant")]
    Assistant {
        text: String,
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        tool_calls: Vec<ToolCall>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        reasoning_content: Option<String>,
    },
    #[serde(rename = "tool")]
    Tool {
        tool_call_id: String,
        name: String,
        content: String,
    },
    #[serde(rename = "system")]
    System { text: String },
    /// A command the user ran from the composer with `!`, and what it printed.
    ///
    /// It is the user's output, not the model's: it is shown in the transcript
    /// and kept with the session, but never sent to the model.
    #[serde(rename = "shell")]
    Shell {
        command: String,
        output: String,
        code: i32,
    },
    #[serde(rename = "error")]
    Error { text: String },
    #[serde(rename = "compaction")]
    Compaction {
        summary: String,
        through: i64,
        #[serde(default)]
        files: Vec<String>,
    },
}

impl Message {
    pub fn type_name(&self) -> &'static str {
        match self {
            Message::User { .. } => "user",
            Message::Assistant { .. } => "assistant",
            Message::Tool { .. } => "tool",
            Message::System { .. } => "system",
            Message::Shell { .. } => "shell",
            Message::Error { .. } => "error",
            Message::Compaction { .. } => "compaction",
        }
    }

    pub fn text(&self) -> &str {
        match self {
            Message::User { text }
            | Message::Assistant { text, .. }
            | Message::System { text }
            | Message::Error { text } => text,
            Message::Tool { content, .. } => content,
            Message::Shell { output, .. } => output,
            Message::Compaction { summary, .. } => summary,
        }
    }

    pub fn reasoning(&self) -> Option<&str> {
        match self {
            Message::Assistant {
                reasoning_content, ..
            } => reasoning_content.as_deref().filter(|text| !text.is_empty()),
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
