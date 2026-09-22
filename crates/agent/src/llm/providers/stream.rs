use async_trait::async_trait;
use serde::de::DeserializeOwned;

use crate::llm::providers::acc::ToolAcc;
use crate::llm::request::{LlmRequest, LlmResponse, Usage};
use crate::llm::{LlmError, Progress, response_lines, status_error};
use crate::session::model::ToolCall;

const DATA: &str = "data: ";
const DONE: &str = "[DONE]";

#[derive(Default)]
pub struct Parts {
    pub text: String,
    pub reasoning: String,
    pub usage: Usage,
    pub finish_reason: Option<String>,
    pub hit_limit: bool,
    pub complete: bool,
    pub acc: ToolAcc,
}

#[async_trait]
pub trait Api: Send + Sync {
    type Event: DeserializeOwned;

    async fn send(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest<'_>,
    ) -> Result<reqwest::Response, LlmError>;

    fn read(
        &self,
        event: Self::Event,
        parts: &mut Parts,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Progress;

    fn finished(&self, parts: &Parts) -> Result<(), LlmError> {
        if parts.complete {
            Ok(())
        } else {
            Err(LlmError::truncated_stream())
        }
    }

    fn settle(&self, parts: &Parts, tool_calls: &[ToolCall]) -> Result<(), LlmError> {
        if tool_calls.is_empty() && parts.hit_limit {
            return Err(LlmError::output_limit());
        }
        let _ = parts;
        Ok(())
    }
}

pub async fn stream<A: Api>(
    api: &A,
    client: &reqwest::Client,
    request: &LlmRequest<'_>,
    on_delta: &mut (dyn FnMut(String) + Send),
) -> Result<LlmResponse, LlmError> {
    let response = api.send(client, request).await?;
    if !response.status().is_success() {
        return Err(status_error(response).await);
    }
    let mut parts = Parts::default();
    response_lines(response, |line| {
        let Some(data) = line.strip_prefix(DATA) else {
            return Progress::Keepalive;
        };
        if data == DONE {
            parts.complete = true;
            return Progress::Made;
        }
        match serde_json::from_str::<A::Event>(data) {
            Ok(event) => api.read(event, &mut parts, on_delta),
            Err(_) => Progress::Keepalive,
        }
    })
    .await?;
    api.finished(&parts)?;
    let tool_calls = std::mem::take(&mut parts.acc).finish()?;
    api.settle(&parts, &tool_calls)?;
    Ok(LlmResponse {
        text: parts.text,
        tool_calls,
        reasoning_content: (!parts.reasoning.is_empty()).then_some(parts.reasoning),
        usage: (parts.usage.total() > 0).then_some(parts.usage),
    })
}
