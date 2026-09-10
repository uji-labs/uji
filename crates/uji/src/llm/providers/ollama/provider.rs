use async_trait::async_trait;

use crate::llm::{
    Auth, Llm, LlmConfig, LlmError, LlmRequest, LlmResponse, response_lines, status_error,
};

use super::transformer::{OllamaChunk, OllamaRequest, OllamaResponse};

pub struct Ollama {
    pub base_url: String,
    pub auth: Auth,
}

impl Ollama {
    pub fn new(config: &LlmConfig) -> Self {
        let auth = match &config.api_key {
            Some(key) => Auth::Bearer { token: key.clone() },
            None => std::env::var("OLLAMA_API_KEY")
                .ok()
                .filter(|key| !key.is_empty())
                .map_or(Auth::None, |token| Auth::Bearer { token }),
        };
        Self {
            base_url: config
                .base_url
                .clone()
                .unwrap_or_else(|| "http://localhost:11434".into()),
            auth,
        }
    }

    async fn post(
        &self,
        client: &reqwest::Client,
        request: &OllamaRequest,
    ) -> Result<reqwest::Response, LlmError> {
        let url = format!("{}/api/chat", self.base_url);
        self.auth
            .apply(client.post(&url))
            .json(request)
            .send()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))
    }
}

#[async_trait]
impl Llm for Ollama {
    fn id(&self) -> &'static str {
        "ollama"
    }

    async fn send_request(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
    ) -> Result<LlmResponse, LlmError> {
        let provider_request = OllamaRequest::from(request);
        let response = self.post(client, &provider_request).await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }
        let body = response
            .text()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))?;
        let parsed: OllamaResponse =
            serde_json::from_str(&body).map_err(|err| LlmError::Provider(err.to_string()))?;
        let text = parsed.text();
        if text.is_empty() {
            return Err(LlmError::Provider("empty response".into()));
        }
        Ok(LlmResponse {
            text: text.to_string(),
            tool_calls: Vec::new(),
        })
    }

    async fn stream(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError> {
        let mut provider_request = OllamaRequest::from(request);
        provider_request.stream = true;
        let response = self.post(client, &provider_request).await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }

        let mut full = String::new();
        response_lines(response, |line| {
            if line.is_empty() {
                return;
            }
            if let Ok(chunk) = serde_json::from_str::<OllamaChunk>(line)
                && let Some(delta) = chunk.delta_text()
            {
                on_delta(delta.to_string());
                full.push_str(delta);
            }
        })
        .await?;
        Ok(LlmResponse {
            text: full,
            tool_calls: Vec::new(),
        })
    }
}
