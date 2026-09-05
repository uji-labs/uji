use std::io::{BufRead, BufReader};

use crate::llm::{Auth, Llm, LlmConfig, LlmError, LlmRequest, status_error};

use super::transformer::{OpenAiChunk, OpenAiRequest, OpenAiResponse};

pub struct OpenAi {
    pub base_url: String,
    pub auth: Auth,
    client: reqwest::blocking::Client,
}

impl OpenAi {
    pub fn new(config: &LlmConfig) -> Self {
        let auth = match &config.api_key {
            Some(key) => Auth::Bearer { token: key.clone() },
            None => std::env::var("OPENAI_API_KEY")
                .ok()
                .filter(|key| !key.is_empty())
                .map_or(Auth::None, |token| Auth::Bearer { token }),
        };
        Self {
            base_url: config
                .base_url
                .clone()
                .unwrap_or_else(|| "https://api.openai.com/v1".into()),
            auth,
            client: reqwest::blocking::Client::new(),
        }
    }

    fn post(&self, request: &OpenAiRequest) -> Result<reqwest::blocking::Response, LlmError> {
        let url = format!("{}/chat/completions", self.base_url);
        self.auth
            .apply(self.client.post(&url))
            .json(request)
            .send()
            .map_err(|err| LlmError::Http(err.to_string()))
    }
}

impl Llm for OpenAi {
    fn id(&self) -> &'static str {
        "openai"
    }

    fn send_request(&self, request: &LlmRequest) -> Result<String, LlmError> {
        let provider_request = OpenAiRequest::from(request);
        let response = self.post(&provider_request)?;
        if !response.status().is_success() {
            return Err(status_error(response));
        }
        let body = response
            .text()
            .map_err(|err| LlmError::Http(err.to_string()))?;
        let parsed: OpenAiResponse =
            serde_json::from_str(&body).map_err(|err| LlmError::Provider(err.to_string()))?;
        parsed
            .text()
            .map(str::to_string)
            .ok_or_else(|| LlmError::Provider("empty response".into()))
    }

    fn stream(
        &self,
        request: &LlmRequest,
        on_delta: &mut dyn FnMut(&str),
    ) -> Result<String, LlmError> {
        let mut provider_request = OpenAiRequest::from(request);
        provider_request.stream = true;
        let response = self.post(&provider_request)?;
        if !response.status().is_success() {
            return Err(status_error(response));
        }

        let mut full = String::new();
        let reader = BufReader::new(response);
        for line in reader.lines() {
            let line = line.map_err(|err| LlmError::Http(err.to_string()))?;
            let Some(data) = line.strip_prefix("data: ") else {
                continue;
            };
            if data.trim() == "[DONE]" {
                break;
            }
            let Ok(chunk) = serde_json::from_str::<OpenAiChunk>(data) else {
                continue;
            };
            if let Some(delta) = chunk.delta_text() {
                on_delta(delta);
                full.push_str(delta);
            }
        }
        Ok(full)
    }
}
