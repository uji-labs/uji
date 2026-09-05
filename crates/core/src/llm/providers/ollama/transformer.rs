use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::session::model::Message;

#[derive(Serialize)]
pub struct OllamaRequest {
    pub model: String,
    pub messages: Vec<OllamaMessage>,
    pub stream: bool,
}

#[derive(Serialize)]
pub struct OllamaMessage {
    pub role: &'static str,
    pub content: String,
}

impl From<&LlmRequest> for OllamaRequest {
    fn from(request: &LlmRequest) -> Self {
        let mut messages = Vec::with_capacity(request.messages.len() + 1);
        if let Some(system) = &request.system {
            messages.push(OllamaMessage {
                role: "system",
                content: system.clone(),
            });
        }
        for message in &request.messages {
            let (role, content) = match message {
                Message::User { text } => ("user", text),
                Message::Assistant { text } => ("assistant", text),
                Message::System { text } => ("system", text),
            };
            messages.push(OllamaMessage {
                role,
                content: content.clone(),
            });
        }
        Self {
            model: request.model.clone(),
            messages,
            stream: false,
        }
    }
}

#[derive(Deserialize)]
pub struct OllamaResponse {
    pub message: Option<OllamaContent>,
}

#[derive(Deserialize)]
pub struct OllamaContent {
    pub content: String,
}

impl OllamaResponse {
    pub fn text(&self) -> &str {
        self.message.as_ref().map_or("", |message| &message.content)
    }
}

#[derive(Deserialize)]
pub struct OllamaChunk {
    pub message: Option<OllamaContent>,
    pub done: bool,
}

impl OllamaChunk {
    pub fn delta_text(&self) -> Option<&str> {
        let content = self.message.as_ref().map_or("", |message| &message.content);
        if content.is_empty() {
            None
        } else {
            Some(content)
        }
    }
}
