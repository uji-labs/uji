use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::session::model::Message;

#[derive(Serialize)]
pub struct AnthropicRequest {
    pub model: String,
    pub max_tokens: u32,
    pub system: String,
    pub messages: Vec<AnthropicMessage>,
    pub stream: bool,
}

#[derive(Serialize)]
pub struct AnthropicMessage {
    pub role: &'static str,
    pub content: String,
}

impl From<&LlmRequest> for AnthropicRequest {
    fn from(request: &LlmRequest) -> Self {
        let mut system = request.system.clone().unwrap_or_default();
        let mut messages = Vec::with_capacity(request.messages.len());
        for message in &request.messages {
            match message {
                Message::User { text } => messages.push(AnthropicMessage {
                    role: "user",
                    content: text.clone(),
                }),
                Message::Assistant { text } => messages.push(AnthropicMessage {
                    role: "assistant",
                    content: text.clone(),
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
        Self {
            model: request.model.clone(),
            max_tokens: 8192,
            system,
            messages,
            stream: false,
        }
    }
}

#[derive(Deserialize)]
pub struct AnthropicResponse {
    pub content: Vec<AnthropicText>,
}

#[derive(Deserialize)]
pub struct AnthropicText {
    pub text: String,
}

impl AnthropicResponse {
    pub fn text(&self) -> String {
        self.content.iter().map(|c| c.text.as_str()).collect()
    }
}

#[derive(Deserialize)]
pub struct AnthropicStreamEvent {
    #[serde(rename = "type")]
    pub kind: String,
    pub delta: Option<AnthropicDelta>,
}

#[derive(Deserialize)]
pub struct AnthropicDelta {
    #[serde(rename = "type")]
    pub kind: String,
    pub text: Option<String>,
}

impl AnthropicStreamEvent {
    pub fn delta_text(&self) -> Option<&str> {
        if self.kind == "content_block_delta" {
            self.delta.as_ref().and_then(|d| d.text.as_deref())
        } else {
            None
        }
    }
}
