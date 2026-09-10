use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::session::model::{Message, ToolCall};

#[derive(Serialize)]
pub struct GeminiRequest {
    #[serde(rename = "systemInstruction", skip_serializing_if = "Option::is_none")]
    pub system_instruction: Option<GeminiInstruction>,
    pub contents: Vec<GeminiContent>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<GeminiTool>,
}

#[derive(Serialize)]
pub struct GeminiTool {
    #[serde(rename = "functionDeclarations")]
    pub function_declarations: Vec<GeminiFunctionDecl>,
}

#[derive(Serialize)]
pub struct GeminiFunctionDecl {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

#[derive(Serialize)]
pub struct GeminiInstruction {
    pub parts: Vec<GeminiPart>,
}

#[derive(Serialize)]
pub struct GeminiContent {
    pub role: &'static str,
    pub parts: Vec<GeminiPart>,
}

#[derive(Serialize, Deserialize)]
#[serde(untagged)]
pub enum GeminiPart {
    Text {
        text: String,
    },
    FunctionCall {
        #[serde(rename = "functionCall")]
        function_call: GeminiFunctionCall,
    },
    FunctionResponse {
        #[serde(rename = "functionResponse")]
        function_response: GeminiFunctionResponse,
    },
}

#[derive(Serialize, Deserialize)]
pub struct GeminiFunctionCall {
    pub name: String,
    pub args: serde_json::Value,
}

#[derive(Serialize, Deserialize)]
pub struct GeminiFunctionResponse {
    pub name: String,
    pub response: serde_json::Value,
}

impl From<&LlmRequest> for GeminiRequest {
    fn from(request: &LlmRequest) -> Self {
        let mut system = request.system.clone().unwrap_or_default();
        let mut contents = Vec::with_capacity(request.messages.len());
        for item in &request.messages {
            match item {
                Message::User { text } => contents.push(GeminiContent {
                    role: "user",
                    parts: vec![GeminiPart::Text { text: text.clone() }],
                }),
                Message::Assistant {
                    text, tool_calls, ..
                } => {
                    let mut parts = Vec::new();
                    if !text.is_empty() {
                        parts.push(GeminiPart::Text { text: text.clone() });
                    }
                    for call in tool_calls {
                        let args = serde_json::from_str(&call.arguments)
                            .unwrap_or(serde_json::Value::Null);
                        parts.push(GeminiPart::FunctionCall {
                            function_call: GeminiFunctionCall {
                                name: call.name.clone(),
                                args,
                            },
                        });
                    }
                    contents.push(GeminiContent {
                        role: "model",
                        parts,
                    });
                }
                Message::Tool { name, content, .. } => contents.push(GeminiContent {
                    role: "function",
                    parts: vec![GeminiPart::FunctionResponse {
                        function_response: GeminiFunctionResponse {
                            name: name.clone(),
                            response: serde_json::json!({ "result": content }),
                        },
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
        let system_instruction = if system.is_empty() {
            None
        } else {
            Some(GeminiInstruction {
                parts: vec![GeminiPart::Text { text: system }],
            })
        };
        let tools = request
            .tools
            .iter()
            .map(|tool| GeminiTool {
                function_declarations: vec![GeminiFunctionDecl {
                    name: tool.name.clone(),
                    description: tool.description.clone(),
                    parameters: tool.parameters.clone(),
                }],
            })
            .collect();
        Self {
            system_instruction,
            contents,
            tools,
        }
    }
}

#[derive(Deserialize)]
pub struct GeminiResponse {
    pub candidates: Vec<GeminiCandidate>,
}

#[derive(Deserialize)]
pub struct GeminiCandidate {
    pub content: GeminiResponseContent,
}

#[derive(Deserialize)]
pub struct GeminiResponseContent {
    pub parts: Vec<GeminiPart>,
}

impl GeminiResponse {
    pub fn text(&self) -> String {
        self.candidates
            .iter()
            .flat_map(|candidate| candidate.content.parts.iter())
            .filter_map(|part| match part {
                GeminiPart::Text { text } => Some(text.as_str()),
                _ => None,
            })
            .collect()
    }

    pub fn tool_calls(&self) -> Vec<ToolCall> {
        self.candidates
            .iter()
            .flat_map(|candidate| candidate.content.parts.iter())
            .filter_map(|part| match part {
                GeminiPart::FunctionCall { function_call } => Some(ToolCall {
                    id: function_call.name.clone(),
                    name: function_call.name.clone(),
                    arguments: function_call.args.to_string(),
                }),
                _ => None,
            })
            .collect()
    }
}

#[derive(Default)]
pub struct GeminiToolAcc {
    calls: Vec<(usize, String, String)>,
}

impl GeminiToolAcc {
    pub fn apply(&mut self, response: &GeminiResponse) {
        if let Some(candidate) = response.candidates.first() {
            for (index, part) in candidate.content.parts.iter().enumerate() {
                if let GeminiPart::FunctionCall { function_call } = part {
                    let args = function_call.args.to_string();
                    if let Some((_, _, existing)) =
                        self.calls.iter_mut().find(|(i, _, _)| *i == index)
                    {
                        *existing = args;
                    } else {
                        self.calls.push((index, function_call.name.clone(), args));
                    }
                }
            }
        }
    }

    pub fn finish(self) -> Vec<ToolCall> {
        let mut calls = self.calls;
        calls.sort_by_key(|(index, _, _)| *index);
        calls
            .into_iter()
            .map(|(_, name, arguments)| ToolCall {
                id: name.clone(),
                name,
                arguments,
            })
            .collect()
    }
}
