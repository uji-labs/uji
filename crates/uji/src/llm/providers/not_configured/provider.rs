use async_trait::async_trait;

use crate::llm::{Llm, LlmError, LlmRequest, LlmResponse};

pub struct NotConfigured;

#[async_trait]
impl Llm for NotConfigured {
    fn id(&self) -> &'static str {
        ""
    }

    async fn send_request(
        &self,
        _client: &reqwest::Client,
        _request: &LlmRequest,
    ) -> Result<LlmResponse, LlmError> {
        Ok(LlmResponse {
            text: "Please run /login to configure a provider".into(),
            tool_calls: Vec::new(),
        })
    }
}
