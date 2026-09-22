use async_trait::async_trait;

use crate::llm::Progress;
use crate::llm::providers::stream::{Api, Parts, stream};
use tokio::sync::Mutex;

use crate::auth::{self, Tokens};
use crate::credential::{self, Credential};
use crate::llm::{LlmConfig, LlmError, LlmRequest, LlmResponse, OAuthSession, Protocol, send};

use super::transformer::{Request, StreamEvent};

pub struct Anthropic {
    pub base_url: String,
    pub api_key: Option<String>,
    oauth: Option<OAuthSession>,
    tokens: Mutex<Option<Tokens>>,
}

impl Anthropic {
    pub fn new(config: &LlmConfig) -> Self {
        let oauth = config.oauth.clone();
        let tokens = Mutex::new(oauth.as_ref().map(|session| session.tokens.clone()));
        Self {
            base_url: config
                .base_url
                .clone()
                .unwrap_or_else(|| "https://api.anthropic.com/v1".into()),
            api_key: config.resolve_key(),
            oauth,
            tokens,
        }
    }

    fn session(&self) -> Option<&OAuthSession> {
        self.oauth.as_ref()
    }

    async fn bearer(&self, client: &reqwest::Client) -> Result<String, LlmError> {
        let Some(session) = self.session() else {
            return Err(LlmError::Provider("no oauth session".into()));
        };
        let mut guard = self.tokens.lock().await;
        let current = guard
            .clone()
            .ok_or_else(|| LlmError::Provider("no oauth tokens".into()))?;
        if !current.is_expired(auth::flow::now()) {
            return Ok(current.access);
        }
        let refreshed = auth::refresh(client, &session.config, &current.refresh)
            .await
            .map_err(|err| LlmError::Provider(err.to_string()))?;
        if let Err(err) =
            credential::store(&session.provider_id, &Credential::from_tokens(&refreshed))
        {
            return Err(LlmError::Provider(format!(
                "refreshed the session but could not save it: {err}"
            )));
        }
        let access = refreshed.access.clone();
        *guard = Some(refreshed);
        Ok(access)
    }

    async fn post(
        &self,
        client: &reqwest::Client,
        request: &Request<'_>,
    ) -> Result<reqwest::Response, LlmError> {
        let url = format!("{}/messages", self.base_url);
        let mut builder = client.post(&url).header("anthropic-version", "2023-06-01");
        match self.session() {
            Some(session) => {
                builder = builder.bearer_auth(self.bearer(client).await?);
                for (name, value) in &session.config.request_headers {
                    builder = builder.header(name, value);
                }
            }
            None => {
                if let Some(key) = &self.api_key {
                    builder = builder.header("x-api-key", key);
                }
            }
        }
        send(builder, request).await
    }

    fn build<'a>(&self, request: &'a LlmRequest<'a>) -> Request<'a> {
        let mut provider_request = Request::from(request);
        if let Some(prompt) = self
            .session()
            .and_then(|session| session.config.identity_prompt.as_deref())
        {
            provider_request.prepend_system(prompt);
        }
        provider_request
    }
}

#[async_trait]
impl Api for Anthropic {
    type Event = StreamEvent;

    async fn send(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest<'_>,
    ) -> Result<reqwest::Response, LlmError> {
        let mut provider_request = self.build(request);
        provider_request.stream = true;
        self.post(client, &provider_request).await
    }

    fn read(
        &self,
        event: StreamEvent,
        parts: &mut Parts,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Progress {
        let mut moved = false;
        if let Some(delta) = event.text_delta() {
            on_delta(delta.to_string());
            parts.text.push_str(delta);
            moved = true;
        }
        if let Some(input) = event.input_usage() {
            parts.usage.input = input.input;
            parts.usage.cache_read = input.cache_read;
            parts.usage.cache_write = input.cache_write;
            moved = true;
        }
        if let Some(output) = event.output_tokens() {
            parts.usage.output = output;
            moved = true;
        }
        let stopped = event.kind == "message_stop";
        parts.hit_limit |= event.truncated();
        parts.complete |= stopped;
        moved |= stopped;
        moved |= event.accumulate(&mut parts.acc);
        Progress::from(moved)
    }
}

#[async_trait]
impl Protocol for Anthropic {
    async fn call(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest<'_>,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError> {
        stream(self, client, request, on_delta).await
    }
}
