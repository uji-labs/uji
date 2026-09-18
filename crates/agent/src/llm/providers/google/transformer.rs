use std::borrow::Cow;

use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::llm::providers::acc::{ToolAcc, arguments_of};
use crate::session::model::{self as session, ToolCall};

const MAX_TOKENS: &str = "MAX_TOKENS";

#[derive(Debug, Clone, Serialize)]
pub struct GenerationConfig {
    #[serde(rename = "thinkingConfig")]
    pub thinking_config: ThinkingConfig,
}

#[derive(Debug, Clone, Serialize)]
pub struct ThinkingConfig {
    #[serde(rename = "thinkingBudget")]
    pub thinking_budget: u32,
}

#[derive(Serialize)]
pub struct Request<'a> {
    #[serde(rename = "generationConfig", skip_serializing_if = "Option::is_none")]
    pub generation_config: Option<GenerationConfig>,
    #[serde(rename = "systemInstruction", skip_serializing_if = "Option::is_none")]
    pub system_instruction: Option<Instruction<'a>>,
    pub contents: Vec<Content<'a>>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<Tool<'a>>,
}

#[derive(Serialize)]
pub struct Tool<'a> {
    #[serde(rename = "functionDeclarations")]
    pub function_declarations: Vec<FunctionDecl<'a>>,
}

#[derive(Serialize)]
pub struct FunctionDecl<'a> {
    pub name: &'a str,
    pub description: &'a str,
    pub parameters: &'a serde_json::Value,
}

#[derive(Serialize)]
pub struct Instruction<'a> {
    pub parts: Vec<Part<'a>>,
}

#[derive(Serialize)]
pub struct Content<'a> {
    pub role: &'static str,
    pub parts: Vec<Part<'a>>,
}

#[derive(Serialize, Deserialize)]
#[serde(untagged)]
pub enum Part<'a> {
    Text {
        text: Cow<'a, str>,
    },
    FunctionCall {
        #[serde(rename = "functionCall")]
        function_call: FunctionCall<'a>,
    },
    FunctionResponse {
        #[serde(rename = "functionResponse")]
        function_response: FunctionResponse<'a>,
    },
}

#[derive(Serialize, Deserialize)]
pub struct FunctionCall<'a> {
    pub name: Cow<'a, str>,
    pub args: serde_json::Value,
}

#[derive(Serialize, Deserialize)]
pub struct FunctionResponse<'a> {
    pub name: Cow<'a, str>,
    pub response: serde_json::Value,
}

impl<'a> From<&'a LlmRequest<'a>> for Request<'a> {
    fn from(request: &'a LlmRequest<'a>) -> Self {
        let mut system = request.system.unwrap_or_default().to_string();
        let mut contents = Vec::with_capacity(request.messages.len());
        for item in request.messages {
            match item {
                session::Message::User { text } => contents.push(Content {
                    role: "user",
                    parts: vec![Part::Text {
                        text: Cow::Borrowed(text),
                    }],
                }),
                session::Message::Assistant {
                    text, tool_calls, ..
                } => {
                    let mut parts = Vec::new();
                    if !text.is_empty() {
                        parts.push(Part::Text {
                            text: Cow::Borrowed(text),
                        });
                    }
                    for call in tool_calls {
                        let args = arguments_of(&call.arguments);
                        parts.push(Part::FunctionCall {
                            function_call: FunctionCall {
                                name: Cow::Borrowed(&call.name),
                                args,
                            },
                        });
                    }
                    contents.push(Content {
                        role: "model",
                        parts,
                    });
                }
                session::Message::Tool { name, content, .. } => contents.push(Content {
                    role: "function",
                    parts: vec![Part::FunctionResponse {
                        function_response: FunctionResponse {
                            name: Cow::Borrowed(name),
                            response: serde_json::json!({ "result": content }),
                        },
                    }],
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
        let system_instruction = if system.is_empty() {
            None
        } else {
            Some(Instruction {
                parts: vec![Part::Text {
                    text: Cow::Owned(system),
                }],
            })
        };
        let tools = request
            .tools
            .iter()
            .map(|tool| Tool {
                function_declarations: vec![FunctionDecl {
                    name: &tool.name,
                    description: &tool.description,
                    parameters: &tool.parameters,
                }],
            })
            .collect();
        let (_, budget) = crate::llm::fit_thinking(request.effort, request.max_output);
        Self {
            generation_config: (budget > 0).then_some(GenerationConfig {
                thinking_config: ThinkingConfig {
                    thinking_budget: budget,
                },
            }),
            system_instruction,
            contents,
            tools,
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Response {
    #[serde(default)]
    pub candidates: Vec<Candidate>,
    #[serde(default)]
    pub usage_metadata: Option<Usage>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Candidate {
    #[serde(default)]
    pub content: Option<ResponseContent>,
    #[serde(default)]
    pub finish_reason: Option<String>,
}

#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct Usage {
    #[serde(default, rename = "promptTokenCount")]
    pub prompt: u64,
    #[serde(default, rename = "candidatesTokenCount")]
    pub candidates: u64,
    #[serde(default, rename = "cachedContentTokenCount")]
    pub cached: u64,
}

impl From<Usage> for crate::llm::Usage {
    fn from(usage: Usage) -> Self {
        Self {
            input: usage.prompt.saturating_sub(usage.cached),
            output: usage.candidates,
            cache_read: usage.cached,
            cache_write: 0,
        }
    }
}

#[derive(Deserialize)]
pub struct ResponseContent {
    pub parts: Vec<Part<'static>>,
}

impl Response {
    pub fn finished(&self) -> bool {
        self.candidates
            .iter()
            .any(|candidate| candidate.finish_reason.is_some())
    }

    pub fn truncated(&self) -> bool {
        self.candidates
            .iter()
            .any(|candidate| candidate.finish_reason.as_deref() == Some(MAX_TOKENS))
    }

    fn parts(&self) -> impl Iterator<Item = &Part<'static>> {
        self.candidates
            .iter()
            .filter_map(|candidate| candidate.content.as_ref())
            .flat_map(|content| content.parts.iter())
    }

    pub fn text(&self) -> String {
        self.parts()
            .filter_map(|part| match part {
                Part::Text { text } => Some(text.as_ref()),
                _ => None,
            })
            .collect()
    }

    pub fn tool_calls(&self) -> Vec<ToolCall> {
        self.parts()
            .filter_map(|part| match part {
                Part::FunctionCall { function_call } => Some(ToolCall {
                    id: function_call.name.to_string(),
                    name: function_call.name.to_string(),
                    arguments: function_call.args.to_string(),
                }),
                _ => None,
            })
            .collect()
    }
}

impl Response {
    pub fn accumulate(&self, acc: &mut ToolAcc) {
        let Some(content) = self
            .candidates
            .first()
            .and_then(|candidate| candidate.content.as_ref())
        else {
            return;
        };
        for (index, part) in content.parts.iter().enumerate() {
            if let Part::FunctionCall { function_call } = part {
                let entry = acc.entry(index);
                entry.name = function_call.name.to_string();
                entry.id.clone_from(&entry.name);
                entry.arguments = function_call.args.to_string();
            }
        }
    }
}
