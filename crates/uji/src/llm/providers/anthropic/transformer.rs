use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::session::model::{Message, ToolCall};

#[derive(Serialize)]
pub struct AnthropicRequest {
    pub model: String,
    pub max_tokens: u32,
    pub system: String,
    pub messages: Vec<AnthropicMessage>,
    pub stream: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<AnthropicTool>,
}

#[derive(Serialize)]
pub struct AnthropicTool {
    pub name: String,
    pub description: String,
    pub input_schema: serde_json::Value,
}

#[derive(Serialize)]
pub struct AnthropicMessage {
    pub role: &'static str,
    pub content: Vec<AnthropicBlock>,
}

#[derive(Serialize)]
#[serde(tag = "type")]
pub enum AnthropicBlock {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "tool_use")]
    ToolUse {
        id: String,
        name: String,
        input: serde_json::Value,
    },
    #[serde(rename = "tool_result")]
    ToolResult {
        tool_use_id: String,
        content: String,
    },
}

impl From<&LlmRequest> for AnthropicRequest {
    fn from(request: &LlmRequest) -> Self {
        let mut system = request.system.clone().unwrap_or_default();
        let mut messages = Vec::with_capacity(request.messages.len());
        for item in &request.messages {
            match item {
                Message::User { text } => messages.push(AnthropicMessage {
                    role: "user",
                    content: vec![AnthropicBlock::Text { text: text.clone() }],
                }),
                Message::Assistant {
                    text, tool_calls, ..
                } => {
                    let mut blocks = Vec::new();
                    if !text.is_empty() {
                        blocks.push(AnthropicBlock::Text { text: text.clone() });
                    }
                    for call in tool_calls {
                        let input = serde_json::from_str(&call.arguments)
                            .unwrap_or(serde_json::Value::Null);
                        blocks.push(AnthropicBlock::ToolUse {
                            id: call.id.clone(),
                            name: call.name.clone(),
                            input,
                        });
                    }
                    messages.push(AnthropicMessage {
                        role: "assistant",
                        content: blocks,
                    });
                }
                Message::Tool {
                    tool_call_id,
                    content,
                    ..
                } => messages.push(AnthropicMessage {
                    role: "user",
                    content: vec![AnthropicBlock::ToolResult {
                        tool_use_id: tool_call_id.clone(),
                        content: content.clone(),
                    }],
                }),
                Message::System { text } => {
                    if !system.is_empty() {
                        system.push('\n');
                    }
                    system.push_str(text);
                }
                Message::Error { .. } => {}
            }
        }
        let tools = request
            .tools
            .iter()
            .map(|tool| AnthropicTool {
                name: tool.name.clone(),
                description: tool.description.clone(),
                input_schema: tool.parameters.clone(),
            })
            .collect();
        Self {
            model: request.model.clone(),
            max_tokens: 8192,
            system,
            messages,
            stream: false,
            tools,
        }
    }
}

#[derive(Deserialize)]
pub struct AnthropicResponse {
    pub content: Vec<AnthropicOutBlock>,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
pub enum AnthropicOutBlock {
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "tool_use")]
    ToolUse {
        id: String,
        name: String,
        input: serde_json::Value,
    },
}

impl AnthropicResponse {
    pub fn text(&self) -> String {
        self.content
            .iter()
            .filter_map(|block| match block {
                AnthropicOutBlock::Text { text } => Some(text.as_str()),
                AnthropicOutBlock::ToolUse { .. } => None,
            })
            .collect()
    }

    pub fn tool_calls(&self) -> Vec<ToolCall> {
        self.content
            .iter()
            .filter_map(|block| match block {
                AnthropicOutBlock::ToolUse { id, name, input } => Some(ToolCall {
                    id: id.clone(),
                    name: name.clone(),
                    arguments: input.to_string(),
                }),
                AnthropicOutBlock::Text { .. } => None,
            })
            .collect()
    }
}

#[derive(Deserialize)]
pub struct AnthropicStreamEvent {
    #[serde(rename = "type")]
    pub kind: String,
    pub index: Option<usize>,
    pub content_block: Option<AnthropicStreamBlock>,
    pub delta: Option<AnthropicStreamDelta>,
}

#[derive(Deserialize)]
pub struct AnthropicStreamBlock {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
}

#[derive(Deserialize)]
pub struct AnthropicStreamDelta {
    #[serde(rename = "type")]
    pub kind: String,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub partial_json: Option<String>,
}

impl AnthropicStreamEvent {
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

#[derive(Default)]
pub struct AnthropicToolAcc {
    calls: Vec<(usize, String, String, String)>,
}

impl AnthropicToolAcc {
    pub fn apply(&mut self, event: &AnthropicStreamEvent) {
        match event.kind.as_str() {
            "content_block_start" => {
                if let Some(block) = &event.content_block
                    && block.kind == "tool_use"
                    && let Some(index) = event.index
                {
                    self.calls.push((
                        index,
                        block.id.clone().unwrap_or_default(),
                        block.name.clone().unwrap_or_default(),
                        String::new(),
                    ));
                }
            }
            "content_block_delta" => {
                if let (Some(index), Some(delta)) = (event.index, &event.delta)
                    && delta.kind == "input_json_delta"
                    && let Some((_, _, _, json)) =
                        self.calls.iter_mut().find(|(i, _, _, _)| *i == index)
                    && let Some(fragment) = &delta.partial_json
                {
                    json.push_str(fragment);
                }
            }
            _ => {}
        }
    }

    pub fn finish(self) -> Vec<ToolCall> {
        let mut calls = self.calls;
        calls.sort_by_key(|(index, _, _, _)| *index);
        calls
            .into_iter()
            .map(|(_, id, name, arguments)| ToolCall {
                id,
                name,
                arguments,
            })
            .collect()
    }
}
