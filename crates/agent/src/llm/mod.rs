pub mod agent;
pub mod cancel;
pub mod catalog;
pub mod context;
pub mod discover;
pub mod error;
pub mod event;
pub mod prompt;
pub mod providers;
pub mod request;
pub mod summary;
pub mod title;
pub mod tuning;
pub mod wire;

use async_trait::async_trait;

pub use agent::{AgentConfig, LuaToolSpec, MAX_TOOL_ITERATIONS, run_agent};
pub use cancel::CancelToken;
pub use catalog::{
    Budget, Catalog, Compat, CompatOverrides, LlmConfig, MAX_RESERVE, MaxTokensField, Model,
    OAuthSession, Origin, Provider, Selection, ThinkingFormat, Wire, authenticated, resolve,
    resolve_from_storage,
};
pub use error::{HttpError, LlmError};
pub(crate) use error::{RETRY_ATTEMPTS, backoff, clip, send, status_error};
pub use event::{StreamEvent, ToolDecision};
pub use prompt::{DEFAULT_SYSTEM_PROMPT, system_prompt};
pub use providers::anthropic::Anthropic;
pub use providers::google::Gemini;
pub use providers::not_configured::NotConfigured;
pub use providers::openai::OpenAi;
pub use request::{LlmRequest, LlmResponse, ToolSpec, Usage};
pub use tuning::{DEFAULT_MAX_OUTPUT, Effort, MIN_ANSWER_TOKENS, Retention, fit_thinking};
pub use wire::Progress;
pub use wire::http_client;
pub(crate) use wire::response_lines;

/// A provider's wire protocol. One call, one response; text arrives through
/// `on_delta` as it streams. Callers that do not care about deltas pass
/// [`Protocol::silent`].
#[async_trait]
pub trait Protocol: Send + Sync {
    async fn call(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest<'_>,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError>;
}

/// A delta sink for callers that only want the final response.
pub fn silent() -> impl FnMut(String) + Send {
    |_| {}
}

/// Every backend uji can talk to. A closed set, so calls dispatch statically.
pub enum Llm {
    Anthropic(Box<Anthropic>),
    OpenAi(OpenAi),
    Gemini(Gemini),
    NotConfigured(NotConfigured),
}

#[async_trait]
impl Protocol for Llm {
    async fn call(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest<'_>,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError> {
        match self {
            Self::Anthropic(llm) => llm.call(client, request, on_delta).await,
            Self::OpenAi(llm) => llm.call(client, request, on_delta).await,
            Self::Gemini(llm) => llm.call(client, request, on_delta).await,
            Self::NotConfigured(llm) => llm.call(client, request, on_delta).await,
        }
    }
}
