use serde::{Deserialize, Serialize};

use crate::llm::LlmRequest;
use crate::session::model::Message;

#[derive(Serialize)]
pub struct OpenAiRequest {
    pub model: String,
    pub messages: Vec<OpenAiMessage>,
    pub stream: bool,
}

#[derive(Serialize)]
pub struct OpenAiMessage {
    pub role: &'static str,
    pub content: String,
}

impl From<&LlmRequest> for OpenAiRequest {
    fn from(request: &LlmRequest) -> Self {
        let mut messages = Vec::with_capacity(request.messages.len() + 1);
        if let Some(system) = &request.system {
            messages.push(OpenAiMessage {
                role: "system",
                content: system.clone(),
            });
        }
        for message in &request.messages {
            let (role, content) = match message {
                Message::User { text } => ("user", text),
                Message::Assistant { text } => ("assistant", text),
                Message::System { text } => ("system", text),
                Message::Error { .. } => continue,
            };
            messages.push(OpenAiMessage {
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
pub struct OpenAiResponse {
    pub choices: Vec<OpenAiChoice>,
}

#[derive(Deserialize)]
pub struct OpenAiChoice {
    pub message: OpenAiContent,
}

#[derive(Deserialize)]
pub struct OpenAiContent {
    pub content: Option<String>,
}

impl OpenAiResponse {
    pub fn text(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.message.content.as_deref())
    }
}

#[derive(Deserialize)]
pub struct OpenAiChunk {
    pub choices: Vec<OpenAiDelta>,
}

#[derive(Deserialize)]
pub struct OpenAiDelta {
    pub delta: OpenAiContent,
}

impl OpenAiChunk {
    pub fn delta_text(&self) -> Option<&str> {
        self.choices
            .first()
            .and_then(|choice| choice.delta.content.as_deref())
    }
}
