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
        let text = parsed
            .text()
            .map(str::to_string)
            .ok_or_else(|| LlmError::Provider("empty response".into()))?;
        let tool_calls = parsed.tool_calls();
        Ok(LlmResponse { text, tool_calls })
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
                acc.apply(&chunk);
            }
        })
        .await?;
        let tool_calls = acc.finish();
        Ok(LlmResponse {
            text: full,
            tool_calls,
        })
    }
}
