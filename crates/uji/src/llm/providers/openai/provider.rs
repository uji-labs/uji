use async_trait::async_trait;

use crate::llm::{
    Auth, Llm, LlmConfig, LlmError, LlmRequest, LlmResponse, response_lines, status_error,
};

use super::transformer::{OpenAiChunk, OpenAiRequest, OpenAiResponse, OpenAiToolAcc};

pub struct OpenAi {
    pub base_url: String,
    pub auth: Auth,
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
        }
    }

    async fn post(
        &self,
        client: &reqwest::Client,
        request: &OpenAiRequest,
    ) -> Result<reqwest::Response, LlmError> {
        let url = format!("{}/chat/completions", self.base_url);
        self.auth
            .apply(client.post(&url))
            .json(request)
            .send()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))
    }
}

fn truncated(finish_reason: Option<&str>) -> Result<(), LlmError> {
    if finish_reason == Some("length") {
        return Err(LlmError::Provider(
            "response hit the model's output limit and was cut off".into(),
        ));
    }
    Ok(())
}

#[async_trait]
impl Llm for OpenAi {
    fn id(&self) -> &'static str {
        "openai"
    }

    async fn send_request(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
    ) -> Result<LlmResponse, LlmError> {
        let provider_request = OpenAiRequest::from(request);
        let response = self.post(client, &provider_request).await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }
        let body = response
            .text()
            .await
            .map_err(|err| LlmError::Http(err.to_string()))?;
        let parsed: OpenAiResponse =
            serde_json::from_str(&body).map_err(|err| LlmError::Provider(err.to_string()))?;
        let text = parsed.text().unwrap_or_default().to_string();
        let tool_calls = parsed.tool_calls();
        if tool_calls.is_empty() {
            truncated(parsed.finish_reason())?;
            if text.is_empty() {
                return Err(LlmError::Provider("empty response".into()));
            }
        }
        let reasoning_content = parsed.reasoning_content().map(str::to_string);
        Ok(LlmResponse {
            text,
            tool_calls,
            reasoning_content,
        })
    }

    async fn stream(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError> {
        let mut provider_request = OpenAiRequest::from(request);
        provider_request.stream = true;
        let response = self.post(client, &provider_request).await?;
        if !response.status().is_success() {
            return Err(status_error(response).await);
        }

        let mut full = String::new();
        let mut reasoning = String::new();
        let mut finish_reason = None;
        let mut acc = OpenAiToolAcc::default();
        response_lines(response, |line| {
            let Some(data) = line.strip_prefix("data: ") else {
                return;
            };
            if data == "[DONE]" {
                return;
            }
            if let Ok(chunk) = serde_json::from_str::<OpenAiChunk>(data) {
                if let Some(delta) = chunk.delta_text() {
                    on_delta(delta.to_string());
                    full.push_str(delta);
                }
                if let Some(delta) = chunk.delta_reasoning() {
                    reasoning.push_str(delta);
                }
                if let Some(reason) = chunk.finish_reason() {
                    finish_reason = Some(reason.to_string());
                }
                acc.apply(&chunk);
            }
        })
        .await?;
        let tool_calls = acc.finish();
        if tool_calls.is_empty() {
            truncated(finish_reason.as_deref())?;
            if full.is_empty() {
                return Err(LlmError::Provider("empty response".into()));
            }
        }
        Ok(LlmResponse {
            text: full,
            tool_calls,
            reasoning_content: (!reasoning.is_empty()).then_some(reasoning),
        })
    }
}
