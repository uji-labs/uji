use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
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
    pub fn text(&self) -> &str {
        match self {
            Self::User { text }
            | Self::Assistant { text, .. }
            | Self::System { text }
            | Self::Error { text }
            | Self::Context { text } => text,
            Self::Tool { content, .. } => content,
            Self::Shell { output, .. } => output,
            Self::Compaction { summary, .. } => summary,
        }
    }
}

#[derive(Debug, Serialize)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Effort {
    Off,
    Minimal,
    Low,
    Medium,
    High,
}

impl Effort {
    pub fn name(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Minimal => "minimal",
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Retention {
    Off,
    Short,
    Long,
}

impl Retention {
    pub fn name(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Short => "short",
            Self::Long => "long",
        }
    }
}
