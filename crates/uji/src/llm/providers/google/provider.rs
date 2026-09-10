use async_trait::async_trait;

use crate::llm::{Llm, LlmConfig, LlmError, LlmRequest, LlmResponse, response_lines, status_error};

use super::transformer::{GeminiRequest, GeminiResponse, GeminiToolAcc};

pub struct Gemini {
    pub base_url: String,
    pub api_key: Option<String>,
}

impl Gemini {
    pub fn new(config: &LlmConfig) -> Self {
        let api_key = config.api_key.clone().or_else(|| {
            std::env::var("GEMINI_API_KEY")
                .or_else(|_| std::env::var("GOOGLE_API_KEY"))
                .ok()
                .filter(|key| !key.is_empty())
        });
        Self {
            base_url: config
                .base_url
                .clone()
                .unwrap_or_else(|| "https://generativelanguage.googleapis.com/v1beta".into()),
            api_key,
        }
    }

    async fn post(
        &self,
        client: &reqwest::Client,
        model: &str,
        stream: bool,
        request: &GeminiRequest,
    ) -> Result<reqwest::Response, LlmError> {
        let suffix = if stream {
            ":streamGenerateContent?alt=sse"
        } else {
            ":generateContent"
        };
        let url = format!("{}/models/{model}{suffix}", self.base_url);
        let mut builder = client.post(&url);
        if let Some(key) = &self.api_key {
            builder = builder.header("x-goog-api-key", key);
        }
        builder
            .json(request)
            .send()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))
    }
}

#[async_trait]
impl Llm for Gemini {
    fn id(&self) -> &'static str {
        "google"
    }

    async fn send_request(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
    ) -> Result<LlmResponse, LlmError> {
        let provider_request = GeminiRequest::from(request);
        let response = self
            .post(client, &request.model, false, &provider_request)
            .await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }
        let body = response
            .text()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))?;
        let parsed: GeminiResponse =
            serde_json::from_str(&body).map_err(|err| LlmError::Provider(err.to_string()))?;
        let text = parsed.text();
        let tool_calls = parsed.tool_calls();
        if text.is_empty() && tool_calls.is_empty() {
            return Err(LlmError::Provider("empty response".into()));
        }
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
        let provider_request = GeminiRequest::from(request);
        let response = self
            .post(client, &request.model, true, &provider_request)
            .await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }

        let mut full = String::new();
        let mut acc = GeminiToolAcc::default();
        response_lines(response, |line| {
            let Some(data) = line.strip_prefix("data: ") else {
                return;
            };
            if let Ok(parsed) = serde_json::from_str::<GeminiResponse>(data) {
                let text = parsed.text();
                if !text.is_empty() {
                    on_delta(text.clone());
                    full.push_str(&text);
                }
                acc.apply(&parsed);
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
