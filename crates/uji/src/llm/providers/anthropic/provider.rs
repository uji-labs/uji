use async_trait::async_trait;

use crate::llm::{Llm, LlmConfig, LlmError, LlmRequest, LlmResponse, response_lines, status_error};

use super::transformer::{
    AnthropicRequest, AnthropicResponse, AnthropicStreamEvent, AnthropicToolAcc,
};

pub struct Anthropic {
    pub base_url: String,
    pub api_key: Option<String>,
}

impl Anthropic {
    pub fn new(config: &LlmConfig) -> Self {
        let api_key = config.api_key.clone().or_else(|| {
            std::env::var("ANTHROPIC_API_KEY")
                .ok()
                .filter(|key| !key.is_empty())
        });
        Self {
            base_url: config
                .base_url
                .clone()
                .unwrap_or_else(|| "https://api.anthropic.com/v1".into()),
            api_key,
        }
    }

    async fn post(
        &self,
        client: &reqwest::Client,
        request: &AnthropicRequest,
    ) -> Result<reqwest::Response, LlmError> {
        let url = format!("{}/messages", self.base_url);
        let mut builder = client.post(&url).header("anthropic-version", "2023-06-01");
        if let Some(key) = &self.api_key {
            builder = builder.header("x-api-key", key);
        }
        builder
            .json(request)
            .send()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))
    }
}

#[async_trait]
impl Llm for Anthropic {
    fn id(&self) -> &'static str {
        "anthropic"
    }

    async fn send_request(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
    ) -> Result<LlmResponse, LlmError> {
        let provider_request = AnthropicRequest::from(request);
        let response = self.post(client, &provider_request).await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }
        let body = response
            .text()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))?;
        let parsed: AnthropicResponse =
            serde_json::from_str(&body).map_err(|err| LlmError::Provider(err.to_string()))?;
        let text = parsed.text();
        if text.is_empty() && parsed.tool_calls().is_empty() {
            return Err(LlmError::Provider("empty response".into()));
        }
        let tool_calls = parsed.tool_calls();
        Ok(LlmResponse {
            text,
            tool_calls,
            reasoning_content: None,
        })
    }

    async fn stream(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError> {
        let mut provider_request = AnthropicRequest::from(request);
        provider_request.stream = true;
        let response = self.post(client, &provider_request).await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }

        let mut full = String::new();
        let mut acc = AnthropicToolAcc::default();
        response_lines(response, |line| {
            let Some(data) = line.strip_prefix("data: ") else {
                return;
            };
            if let Ok(event) = serde_json::from_str::<AnthropicStreamEvent>(data) {
                if let Some(delta) = event.text_delta() {
                    on_delta(delta.to_string());
                    full.push_str(delta);
                }
                acc.apply(&event);
            }
        })
        .await?;
        let tool_calls = acc.finish();
        Ok(LlmResponse {
            text: full,
            tool_calls,
            reasoning_content: None,
        })
    }
}
