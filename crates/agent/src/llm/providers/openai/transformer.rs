use serde::{Deserialize, Serialize};

use crate::llm::providers::acc::{ToolAcc, arguments_of};
use crate::llm::{Compat, LlmRequest, MaxTokensField, ThinkingFormat};
use crate::session::model::{self as session, ToolCall};

#[derive(Serialize)]
pub struct Request<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reasoning_effort: Option<&'static str>,
    /// The output limit, under whichever name this endpoint answers to.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_completion_tokens: Option<u32>,
    /// Endpoint-specific spellings of "think this hard".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reasoning: Option<Reasoning>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<Thinking>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub enable_thinking: Option<bool>,
    pub model: &'a str,
    pub messages: Vec<Message<'a>>,
    pub stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stream_options: Option<StreamOptions>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<Tool<'a>>,
}

#[derive(Serialize)]
pub struct Reasoning {
    pub effort: &'static str,
}

#[derive(Serialize)]
pub struct Thinking {
    #[serde(rename = "type")]
    pub kind: &'static str,
}

#[derive(Serialize)]
pub struct StreamOptions {
    pub include_usage: bool,
}

#[derive(Serialize)]
pub struct Tool<'a> {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub function: ToolFunction<'a>,
}

#[derive(Serialize)]
pub struct ToolFunction<'a> {
    pub name: &'a str,
    pub description: &'a str,
    pub parameters: &'a serde_json::Value,
}

#[derive(Serialize)]
pub struct Message<'a> {
    pub role: &'static str,
    pub content: Option<&'a str>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tool_calls: Vec<Call>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_call_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<&'a str>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct Call {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub function: CallFunction,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct CallFunction {
    pub name: String,
    pub arguments: String,
}

fn message<'a>(role: &'static str, content: Option<&'a str>) -> Message<'a> {
    Message {
        role,
        content,
        tool_calls: Vec::new(),
        tool_call_id: None,
        name: None,
    }
}

impl<'a> Request<'a> {
    pub fn build(request: &'a LlmRequest<'a>, compat: Compat) -> Self {
        let mut messages = Vec::with_capacity(request.messages.len() + 1);
        if let Some(system) = request.system {
            messages.push(message("system", Some(system)));
        }
        for item in request.messages {
            match item {
                session::Message::User { text } => {
                    messages.push(message("user", Some(text.as_str())));
                }
                session::Message::Assistant {
                    text, tool_calls, ..
                } => messages.push(Message {
                    role: "assistant",
                    content: (!text.is_empty()).then_some(text.as_str()),
                    tool_calls: tool_calls
                        .iter()
                        .map(|call| Call {
                            id: call.id.clone(),
                            kind: String::from("function"),
                            function: CallFunction {
                                name: call.name.clone(),
                                arguments: arguments_of(&call.arguments).to_string(),
                            },
                        })
                        .collect(),
                    tool_call_id: None,
                    name: None,
                }),
                session::Message::Tool {
                    tool_call_id,
                    content,
                    name,
                } => messages.push(Message {
                    role: "tool",
                    content: Some(content.as_str()),
                    tool_calls: Vec::new(),
                    tool_call_id: Some(tool_call_id.as_str()),
                    name: compat.tool_result_name.then_some(name.as_str()),
                }),
                session::Message::System { text } => {
                    messages.push(message("system", Some(text.as_str())));
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
                kind: "function",
                function: ToolFunction {
                    name: &tool.name,
                    description: &tool.description,
                    parameters: &tool.parameters,
                },
            })
            .collect();
        let effort = match request.effort {
            crate::llm::Effort::Off => None,
            crate::llm::Effort::Minimal => Some("minimal"),
            crate::llm::Effort::Low => Some("low"),
            crate::llm::Effort::Medium => Some("medium"),
            crate::llm::Effort::High => Some("high"),
        };
        let (limit, _) = crate::llm::fit_thinking(request.effort, request.max_output);
        Self {
            reasoning_effort: match compat.thinking {
                ThinkingFormat::OpenAi => effort,
                _ => None,
            },
            reasoning: match (compat.thinking, effort) {
                (ThinkingFormat::OpenRouter, Some(effort)) => Some(Reasoning { effort }),
                _ => None,
            },
            thinking: match (compat.thinking, effort) {
                (ThinkingFormat::DeepSeek | ThinkingFormat::Zai, Some(_)) => {
                    Some(Thinking { kind: "enabled" })
                }
                (ThinkingFormat::DeepSeek | ThinkingFormat::Zai, None) => {
                    Some(Thinking { kind: "disabled" })
                }
                _ => None,
            },
            enable_thinking: match compat.thinking {
                ThinkingFormat::Qwen => Some(effort.is_some()),
                _ => None,
            },
            max_tokens: (compat.max_tokens_field == MaxTokensField::MaxTokens).then_some(limit),
            max_completion_tokens: (compat.max_tokens_field == MaxTokensField::MaxCompletionTokens)
                .then_some(limit),
            model: request.model,
            messages,
            stream: false,
            stream_options: None,
            tools,
        }
    }
}

#[derive(Deserialize)]
pub struct Response {
    pub choices: Vec<Choice>,
    #[serde(default)]
    pub usage: Option<Usage>,
}

#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Usage {
    #[serde(default)]
    pub prompt_tokens: u64,
    #[serde(default)]
    pub completion_tokens: u64,
    #[serde(default)]
    pub prompt_tokens_details: PromptDetails,
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct PromptDetails {
    #[serde(default)]
    pub cached_tokens: u64,
}

impl From<Usage> for crate::llm::Usage {
    fn from(usage: Usage) -> Self {
        let cache_read = usage.prompt_tokens_details.cached_tokens;
        Self {
            input: usage.prompt_tokens.saturating_sub(cache_read),
            output: usage.completion_tokens,
            cache_read,
            cache_write: 0,
        }
    }
}

#[derive(Deserialize)]
pub struct Choice {
    pub message: MessageOut,
    #[serde(default)]
    pub finish_reason: Option<String>,
}

#[derive(Deserialize)]
pub struct MessageOut {
    #[serde(default)]
    pub content: Option<String>,
    #[serde(default)]
    pub tool_calls: Vec<Call>,
    #[serde(default)]
    pub reasoning_content: Option<String>,
}

impl Response {
    pub fn text(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.message.content.as_deref())
    }

    pub fn reasoning_content(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.message.reasoning_content.as_deref())
    }

    pub fn finish_reason(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.finish_reason.as_deref())
    }

    pub fn tool_calls(&self) -> Vec<ToolCall> {
        self.choices.first().map_or_else(Vec::new, |choice| {
            choice
                .message
                .tool_calls
                .iter()
                .map(|call| ToolCall {
                    id: call.id.clone(),
                    name: call.function.name.clone(),
                    arguments: call.function.arguments.clone(),
                })
                .collect()
        })
    }
}

#[derive(Deserialize)]
pub struct Chunk {
    #[serde(default)]
    pub choices: Vec<Delta>,
    #[serde(default)]
    pub usage: Option<Usage>,
}

#[derive(Deserialize)]
pub struct Delta {
    pub delta: DeltaContent,
    #[serde(default)]
    pub finish_reason: Option<String>,
}

#[derive(Deserialize)]
pub struct DeltaContent {
    #[serde(default)]
    pub content: Option<String>,
    #[serde(default)]
    pub reasoning_content: Option<String>,
    #[serde(default)]
    pub tool_calls: Vec<DeltaToolCall>,
}

#[derive(Deserialize)]
pub struct DeltaToolCall {
    pub index: usize,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub function: Option<DeltaFunction>,
}

#[derive(Deserialize)]
pub struct DeltaFunction {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub arguments: Option<String>,
}

impl Chunk {
    pub fn delta_text(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.delta.content.as_deref())
    }

    pub fn delta_reasoning(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.delta.reasoning_content.as_deref())
    }

    pub fn finish_reason(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.finish_reason.as_deref())
    }
}

impl Chunk {
    pub fn accumulate(&self, acc: &mut ToolAcc) -> bool {
        let Some(choice) = self.choices.first() else {
            return false;
        };
        let took = !choice.delta.tool_calls.is_empty();
        for call in &choice.delta.tool_calls {
            let entry = acc.entry(call.index);
            if let Some(id) = &call.id {
                entry.id.clone_from(id);
            }
            let Some(function) = &call.function else {
                continue;
            };
            if let Some(name) = &function.name {
                entry.name.clone_from(name);
            }
            if let Some(arguments) = &function.arguments {
                entry.arguments.push_str(arguments);
            }
        }
        took
    }
}
