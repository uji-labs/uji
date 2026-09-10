use serde::{Deserialize, Serialize};

use super::id::{MessageId, SessionId};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Time {
    pub created: i64,
    pub updated: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub id: SessionId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<SessionId>,
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
    #[serde(rename = "error")]
    Error { text: String },
}

impl Message {
    pub fn type_name(&self) -> &'static str {
        match self {
            Message::User { .. } => "user",
            Message::Assistant { .. } => "assistant",
            Message::Tool { .. } => "tool",
            Message::System { .. } => "system",
            Message::Error { .. } => "error",
        }
    }

    pub fn text(&self) -> &str {
        match self {
            Message::User { text }
            | Message::Assistant { text, .. }
            | Message::System { text }
            | Message::Error { text } => text,
            Message::Tool { content, .. } => content,
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
