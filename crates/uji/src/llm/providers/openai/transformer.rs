use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::session::model::{Message, ToolCall};

#[derive(Serialize)]
pub struct OpenAiRequest {
    pub model: String,
    pub messages: Vec<OpenAiMessage>,
    pub stream: bool,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<OpenAiTool>,
}

#[derive(Serialize)]
pub struct OpenAiTool {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub function: OpenAiToolFunction,
}

#[derive(Serialize)]
pub struct OpenAiToolFunction {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

#[derive(Serialize)]
pub struct OpenAiMessage {
    pub role: &'static str,
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tool_calls: Vec<OpenAiCall>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_call_id: Option<String>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct OpenAiCall {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub function: OpenAiCallFunction,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct OpenAiCallFunction {
    pub name: String,
    pub arguments: String,
}

fn message(role: &'static str, content: Option<String>) -> OpenAiMessage {
    OpenAiMessage {
        role,
        content,
        tool_calls: Vec::new(),
        tool_call_id: None,
    }
}

impl From<&LlmRequest> for OpenAiRequest {
    fn from(request: &LlmRequest) -> Self {
        let mut messages = Vec::with_capacity(request.messages.len() + 1);
        if let Some(system) = &request.system {
            messages.push(message("system", Some(system.clone())));
        }
        for item in &request.messages {
            match item {
                Message::User { text } => messages.push(message("user", Some(text.clone()))),
                Message::Assistant {
                    text, tool_calls, ..
                } => messages.push(OpenAiMessage {
                    role: "assistant",
                    content: if text.is_empty() {
                        None
                    } else {
                        Some(text.clone())
                    },
                    tool_calls: tool_calls
                        .iter()
                        .map(|call| OpenAiCall {
                            id: call.id.clone(),
                            kind: String::from("function"),
                            function: OpenAiCallFunction {
                                name: call.name.clone(),
                                arguments: call.arguments.clone(),
                            },
                        })
                        .collect(),
                    tool_call_id: None,
                }),
                Message::Tool {
                    tool_call_id,
                    content,
                    ..
                } => messages.push(OpenAiMessage {
                    role: "tool",
                    content: Some(content.clone()),
                    tool_calls: Vec::new(),
                    tool_call_id: Some(tool_call_id.clone()),
                }),
                Message::System { text } => messages.push(message("system", Some(text.clone()))),
                Message::Error { .. } => {}
            }
        }
        let tools = request
            .tools
            .iter()
            .map(|tool| OpenAiTool {
                kind: "function",
                function: OpenAiToolFunction {
                    name: tool.name.clone(),
                    description: tool.description.clone(),
                    parameters: tool.parameters.clone(),
                },
            })
            .collect();
        Self {
            model: request.model.clone(),
            messages,
            stream: false,
            tools,
        }
    }
}

#[derive(Deserialize)]
pub struct OpenAiResponse {
    pub choices: Vec<OpenAiChoice>,
}

#[derive(Deserialize)]
pub struct OpenAiChoice {
    pub message: OpenAiMessageOut,
    #[serde(default)]
    pub finish_reason: Option<String>,
}

#[derive(Deserialize)]
pub struct OpenAiMessageOut {
    #[serde(default)]
    pub content: Option<String>,
    #[serde(default)]
    pub tool_calls: Vec<OpenAiCall>,
    #[serde(default)]
    pub reasoning_content: Option<String>,
}

impl OpenAiResponse {
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
pub struct OpenAiChunk {
    pub choices: Vec<OpenAiDelta>,
}

#[derive(Deserialize)]
pub struct OpenAiDelta {
    pub delta: OpenAiDeltaContent,
    #[serde(default)]
    pub finish_reason: Option<String>,
}

#[derive(Deserialize)]
pub struct OpenAiDeltaContent {
    #[serde(default)]
    pub content: Option<String>,
    #[serde(default)]
    pub reasoning_content: Option<String>,
    #[serde(default)]
    pub tool_calls: Vec<OpenAiDeltaToolCall>,
}

#[derive(Deserialize)]
pub struct OpenAiDeltaToolCall {
    pub index: usize,
    #[serde(default)]
    pub id: Option<String>,
    #[serde(default)]
    pub function: Option<OpenAiDeltaFunction>,
}

#[derive(Deserialize)]
pub struct OpenAiDeltaFunction {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub arguments: Option<String>,
}

impl OpenAiChunk {
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

#[derive(Default)]
pub struct OpenAiToolAcc {
    calls: Vec<(usize, String, String, String)>,
}

impl OpenAiToolAcc {
    pub fn apply(&mut self, chunk: &OpenAiChunk) {
        let Some(choice) = chunk.choices.first() else {
            return;
        };
        for call in &choice.delta.tool_calls {
            if let Some((_, id, name, args)) =
                self.calls.iter_mut().find(|(i, _, _, _)| *i == call.index)
            {
                if let Some(value) = &call.id {
                    id.clone_from(value);
                }
                if let Some(function) = &call.function {
                    if let Some(value) = &function.name {
                        name.clone_from(value);
                    }
                    if let Some(value) = &function.arguments {
                        args.push_str(value);
                    }
                }
            } else {
                let id = call.id.clone().unwrap_or_default();
                let name = call
                    .function
                    .as_ref()
                    .and_then(|f| f.name.clone())
                    .unwrap_or_default();
                let arguments = call
                    .function
                    .as_ref()
                    .and_then(|f| f.arguments.clone())
                    .unwrap_or_default();
                self.calls.push((call.index, id, name, arguments));
            }
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
