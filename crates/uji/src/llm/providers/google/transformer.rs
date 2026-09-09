use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::session::model::Message;

#[derive(Serialize)]
pub struct GeminiRequest {
    #[serde(rename = "systemInstruction", skip_serializing_if = "Option::is_none")]
    pub system_instruction: Option<GeminiInstruction>,
    pub contents: Vec<GeminiContent>,
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
pub struct GeminiPart {
    pub text: String,
}

impl From<&LlmRequest> for GeminiRequest {
    fn from(request: &LlmRequest) -> Self {
        let mut system = request.system.clone().unwrap_or_default();
        let mut contents = Vec::with_capacity(request.messages.len());
        for message in &request.messages {
            match message {
                Message::User { text } => contents.push(GeminiContent {
                    role: "user",
                    parts: vec![GeminiPart { text: text.clone() }],
                }),
                Message::Assistant { text } => contents.push(GeminiContent {
                    role: "model",
                    parts: vec![GeminiPart { text: text.clone() }],
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
                parts: vec![GeminiPart { text: system }],
            })
        };
        Self {
            system_instruction,
            contents,
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
            .flat_map(|c| c.content.parts.iter())
            .map(|p| p.text.as_str())
            .collect()
    }
}
