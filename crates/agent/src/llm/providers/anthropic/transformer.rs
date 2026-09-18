use serde::{Deserialize, Serialize};

use crate::llm::providers::acc::{ToolAcc, arguments_of};
use crate::llm::{LlmRequest, Retention};
use crate::session::model::{self as session, ToolCall};

const MAX_TOKENS: &str = "max_tokens";

#[derive(Debug, Clone, Serialize)]
pub struct Thinking {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub budget_tokens: u32,
}

#[derive(Debug, Clone, Copy, Serialize)]
pub struct CacheControl {
    #[serde(rename = "type")]
    pub kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ttl: Option<&'static str>,
}

impl CacheControl {
    fn new(retention: Retention) -> Option<Self> {
        retention.enabled().then(|| Self {
            kind: "ephemeral",
            ttl: retention.ttl(),
        })
    }
}

#[derive(Serialize)]
pub struct SystemBlock {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cache_control: Option<CacheControl>,
}

impl SystemBlock {
    fn text(text: String) -> Self {
        Self {
            kind: "text",
            text,
            cache_control: None,
        }
    }
}

#[derive(Serialize)]
pub struct Request<'a> {
    pub model: &'a str,
    pub max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<Thinking>,
    pub system: Vec<SystemBlock>,
    pub messages: Vec<Message<'a>>,
    pub stream: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<Tool<'a>>,
}

impl Request<'_> {
    fn cached(mut self, retention: Retention) -> Self {
        let Some(control) = CacheControl::new(retention) else {
            return self;
        };
        if let Some(block) = self.system.last_mut() {
            block.cache_control = Some(control);
        }
        if let Some(tool) = self.tools.last_mut() {
            tool.cache_control = Some(control);
        }
        if let Some(block) = self
            .messages
            .iter_mut()
            .rfind(|message| message.role == "user")
            .and_then(|message| message.content.last_mut())
        {
            block.cache_control = Some(control);
        }
        self
    }

    pub fn prepend_system(&mut self, text: &str) {
        if self.system.first().is_some_and(|block| block.text == text) {
            return;
        }
        self.system.insert(0, SystemBlock::text(text.to_string()));
    }
}

#[derive(Serialize)]
pub struct Tool<'a> {
    pub name: &'a str,
    pub description: &'a str,
    pub input_schema: &'a serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cache_control: Option<CacheControl>,
}

#[derive(Serialize)]
pub struct Message<'a> {
    pub role: &'static str,
    pub content: Vec<Block<'a>>,
}

#[derive(Serialize)]
pub struct Block<'a> {
    #[serde(flatten)]
    pub body: Content<'a>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cache_control: Option<CacheControl>,
}

impl<'a> From<Content<'a>> for Block<'a> {
    fn from(body: Content<'a>) -> Self {
        Self {
            body,
            cache_control: None,
        }
    }
}

#[derive(Serialize)]
#[serde(tag = "type")]
pub enum Content<'a> {
    #[serde(rename = "text")]
    Text { text: &'a str },
    #[serde(rename = "tool_use")]
    ToolUse {
        id: &'a str,
        name: &'a str,
        input: serde_json::Value,
    },
    #[serde(rename = "tool_result")]
    ToolResult {
        tool_use_id: &'a str,
        content: &'a str,
    },
}

impl<'a> From<&'a LlmRequest<'a>> for Request<'a> {
    fn from(request: &'a LlmRequest<'a>) -> Self {
        let mut system = request.system.unwrap_or_default().to_string();
        let mut messages = Vec::with_capacity(request.messages.len());
        for item in request.messages {
            match item {
                session::Message::User { text } => messages.push(Message {
                    role: "user",
                    content: vec![
                        Content::Text {
                            text: text.as_str(),
                        }
                        .into(),
                    ],
                }),
                session::Message::Assistant {
                    text, tool_calls, ..
                } => {
                    let mut blocks = Vec::new();
                    if !text.is_empty() {
                        blocks.push(
                            Content::Text {
                                text: text.as_str(),
                            }
                            .into(),
                        );
                    }
                    for call in tool_calls {
                        let input = arguments_of(&call.arguments);
                        blocks.push(
                            Content::ToolUse {
                                id: &call.id,
                                name: &call.name,
                                input,
                            }
                            .into(),
                        );
                    }
                    messages.push(Message {
                        role: "assistant",
                        content: blocks,
                    });
                }
                session::Message::Tool {
                    tool_call_id,
                    content,
                    ..
                } => messages.push(Message {
                    role: "user",
                    content: vec![
                        Content::ToolResult {
                            tool_use_id: tool_call_id,
                            content,
                        }
                        .into(),
                    ],
                }),
                session::Message::System { text } => {
                    if !system.is_empty() {
                        system.push('\n');
                    }
                    system.push_str(text);
                }
                session::Message::Shell { .. }
                | session::Message::Error { .. }
                | session::Message::Compaction { .. } => {}
            }
        }
        let tools = request
            .tools
            .iter()
            .map(|tool| Tool {
                name: &tool.name,
                description: &tool.description,
                input_schema: &tool.parameters,
                cache_control: None,
            })
            .collect();
        let (max_tokens, budget) = crate::llm::fit_thinking(request.effort, request.max_output);
        Self {
            model: request.model,
            max_tokens,
            thinking: (budget > 0).then_some(Thinking {
                kind: "enabled",
                budget_tokens: budget,
            }),
            system: if system.is_empty() {
                Vec::new()
            } else {
                vec![SystemBlock::text(system)]
            },
            messages,
            stream: false,
            tools,
        }
        .cached(request.cache)
    }
}

#[derive(Deserialize)]
pub struct Response {
    pub content: Vec<OutBlock>,
    #[serde(default)]
    pub stop_reason: Option<String>,
    #[serde(default)]
    pub usage: Option<Usage>,
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct Usage {
    #[serde(default, rename = "input_tokens")]
    pub input: u64,
    #[serde(default, rename = "output_tokens")]
    pub output: u64,
    #[serde(default, rename = "cache_read_input_tokens")]
    pub cache_read: u64,
    #[serde(default, rename = "cache_creation_input_tokens")]
    pub cache_write: u64,
}

impl From<Usage> for crate::llm::Usage {
    fn from(usage: Usage) -> Self {
        Self {
            input: usage.input,
            output: usage.output,
            cache_read: usage.cache_read,
            cache_write: usage.cache_write,
        }
    }
}

#[derive(Deserialize)]
#[serde(tag = "type")]
pub enum OutBlock {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "tool_use")]
    ToolUse {
        id: String,
        name: String,
        input: serde_json::Value,
    },
}

impl Response {
    pub fn truncated(&self) -> bool {
        self.stop_reason.as_deref() == Some(MAX_TOKENS)
    }

    pub fn text(&self) -> String {
        self.content
            .iter()
            .filter_map(|block| match block {
                OutBlock::Text { text } => Some(text.as_str()),
                OutBlock::ToolUse { .. } => None,
            })
            .collect()
    }

    pub fn tool_calls(&self) -> Vec<ToolCall> {
        self.content
            .iter()
            .filter_map(|block| match block {
                OutBlock::ToolUse { id, name, input } => Some(ToolCall {
                    id: id.clone(),
                    name: name.clone(),
                    arguments: input.to_string(),
                }),
                OutBlock::Text { .. } => None,
            })
            .collect()
    }
}

#[derive(Deserialize)]
pub struct StreamEvent {
    #[serde(rename = "type")]
    pub kind: String,
    pub index: Option<usize>,
    pub content_block: Option<StreamBlock>,
    pub delta: Option<StreamDelta>,
    #[serde(default)]
    pub message: Option<StreamMessage>,
    #[serde(default)]
    pub usage: Option<Usage>,
}

#[derive(Deserialize)]
pub struct StreamMessage {
    #[serde(default)]
    pub usage: Option<Usage>,
}

#[derive(Deserialize)]
pub struct StreamBlock {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
}

#[derive(Deserialize)]
pub struct StreamDelta {
    #[serde(rename = "type", default)]
    pub kind: String,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub partial_json: Option<String>,
    #[serde(default)]
    pub stop_reason: Option<String>,
}

impl StreamEvent {
    pub fn truncated(&self) -> bool {
        self.delta
            .as_ref()
            .and_then(|delta| delta.stop_reason.as_deref())
            == Some(MAX_TOKENS)
    }

    pub fn input_usage(&self) -> Option<crate::llm::Usage> {
        self.message
            .as_ref()
            .and_then(|message| message.usage)
            .map(|usage| crate::llm::Usage {
                output: 0,
                ..usage.into()
            })
    }

    pub fn output_tokens(&self) -> Option<u64> {
        self.usage.map(|usage| usage.output)
    }

    pub fn text_delta(&self) -> Option<&str> {
        if self.kind == "content_block_delta" {
            self.delta.as_ref().and_then(|delta| {
                if delta.kind == "text_delta" {
                    delta.text.as_deref()
                } else {
                    None
                }
            })
        } else {
            None
        }
    }
}

impl StreamEvent {
    pub fn accumulate(&self, acc: &mut ToolAcc) {
        let Some(index) = self.index else {
            return;
        };
        match self.kind.as_str() {
            "content_block_start" => {
                if let Some(block) = &self.content_block
                    && block.kind == "tool_use"
                {
                    let entry = acc.entry(index);
                    entry.id = block.id.clone().unwrap_or_default();
                    entry.name = block.name.clone().unwrap_or_default();
                }
            }
            "content_block_delta" => {
                if let Some(delta) = &self.delta
                    && delta.kind == "input_json_delta"
                    && let Some(fragment) = &delta.partial_json
                {
                    acc.entry(index).arguments.push_str(fragment);
                }
            }
            _ => {}
        }
    }
}
