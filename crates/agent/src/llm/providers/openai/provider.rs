use async_trait::async_trait;

use crate::llm::Progress;
use crate::llm::providers::stream::{Api, Parts, stream};
use crate::session::model::ToolCall;

use crate::llm::{Compat, LlmConfig, LlmError, LlmRequest, LlmResponse, Protocol, send};

use super::transformer::{Chunk, Request, StreamOptions};

pub struct OpenAi {
    pub base_url: String,
    pub api_key: Option<String>,
    pub compat: Compat,
}

impl OpenAi {
    pub fn new(config: &LlmConfig) -> Self {
        let base_url = config
            .base_url
            .clone()
            .unwrap_or_else(|| "https://api.openai.com/v1".into());
        Self {
            api_key: config.resolve_key(),
            compat: Compat::resolve(&base_url, config.compat),
            base_url,
        }
    }

    async fn post(
        &self,
        client: &reqwest::Client,
        request: &Request<'_>,
    ) -> Result<reqwest::Response, LlmError> {
        let url = format!("{}/chat/completions", self.base_url);
        let mut builder = client.post(&url);
        if let Some(key) = &self.api_key {
            builder = builder.bearer_auth(key);
        }
        send(builder, request).await
    }
}

fn truncated(finish_reason: Option<&str>) -> Result<(), LlmError> {
    if finish_reason == Some("length") {
        return Err(LlmError::output_limit());
    }
    Ok(())
}

#[async_trait]
impl Api for OpenAi {
    type Event = Chunk;

    async fn send(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest<'_>,
    ) -> Result<reqwest::Response, LlmError> {
        let mut provider_request = Request::build(request, self.compat);
        provider_request.stream = true;
        provider_request.stream_options = Some(StreamOptions {
            include_usage: true,
        });
        self.post(client, &provider_request).await
    }

    fn read(
        &self,
        event: Chunk,
        parts: &mut Parts,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Progress {
        let mut moved = false;
        if let Some(delta) = event.delta_text() {
            on_delta(delta.to_string());
            parts.text.push_str(delta);
            moved = true;
        }
        if let Some(delta) = event.delta_reasoning() {
            parts.reasoning.push_str(delta);
            moved = true;
        }
        if let Some(reason) = event.finish_reason() {
            parts.finish_reason = Some(reason.to_string());
            parts.complete = true;
            moved = true;
        }
        if let Some(reported) = event.usage {
            parts.usage = reported.into();
            moved = true;
        }
        moved |= event.accumulate(&mut parts.acc);
        Progress::from(moved)
    }

    fn finished(&self, parts: &Parts) -> Result<(), LlmError> {
        if parts.complete || !self.compat.finish_reason {
            Ok(())
        } else {
            Err(LlmError::truncated_stream())
        }
    }

    fn settle(&self, parts: &Parts, tool_calls: &[ToolCall]) -> Result<(), LlmError> {
        if !tool_calls.is_empty() {
            return Ok(());
        }
        truncated(parts.finish_reason.as_deref())?;
        if parts.text.is_empty() {
            return Err(LlmError::empty_response());
        }
        Ok(())
    }
}

#[async_trait]
impl Protocol for OpenAi {
    async fn call(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest<'_>,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError> {
        stream(self, client, request, on_delta).await
    }
}
