pub mod providers;

use std::sync::Arc;

use crate::session::model::Message;

pub use providers::echo::Echo;
pub use providers::ollama::Ollama;
pub use providers::openai::OpenAi;

pub enum Auth {
    None,
    Bearer { token: String },
    ApiKey { header: String, key: String },
}

impl Auth {
    pub(crate) fn apply(
        &self,
        builder: reqwest::blocking::RequestBuilder,
    ) -> reqwest::blocking::RequestBuilder {
        match self {
            Auth::None => builder,
            Auth::Bearer { token } => builder.bearer_auth(token),
            Auth::ApiKey { header, key } => builder.header(header.as_str(), key.as_str()),
        }
    }
}

pub struct LlmRequest {
    pub model: String,
    pub system: Option<String>,
    pub messages: Vec<Message>,
}

#[derive(Debug, thiserror::Error)]
pub enum LlmError {
    #[error("http: {0}")]
    Http(String),
    #[error("auth")]
    Auth,
    #[error("provider: {0}")]
    Provider(String),
}

pub(crate) fn status_error(response: reqwest::blocking::Response) -> LlmError {
    let status = response.status().as_u16();
    let body = response.text().unwrap_or_default();
    if status == 401 || status == 403 {
        LlmError::Auth
    } else {
        LlmError::Http(format!("{status}: {body}"))
    }
}

pub trait Llm: Send + Sync {
    fn id(&self) -> &'static str;
    fn send_request(&self, request: &LlmRequest) -> Result<String, LlmError>;
    fn stream(
        &self,
        request: &LlmRequest,
        on_delta: &mut dyn FnMut(&str),
    ) -> Result<String, LlmError> {
        let text = self.send_request(request)?;
        on_delta(&text);
        Ok(text)
    }
}

pub struct LlmConfig {
    pub provider: String,
    pub model: String,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
}

impl Default for LlmConfig {
    fn default() -> Self {
        Self {
            provider: "echo".into(),
            model: String::new(),
            base_url: None,
            api_key: None,
        }
    }
}

struct ProviderSpec {
    id: &'static str,
    create: fn(&LlmConfig) -> Arc<dyn Llm>,
}

fn make_openai(config: &LlmConfig) -> Arc<dyn Llm> {
    Arc::new(OpenAi::new(config))
}

fn make_ollama(config: &LlmConfig) -> Arc<dyn Llm> {
    Arc::new(Ollama::new(config))
}

fn make_echo(_config: &LlmConfig) -> Arc<dyn Llm> {
    Arc::new(Echo)
}

static PROVIDERS: &[ProviderSpec] = &[
    ProviderSpec {
        id: "openai",
        create: make_openai,
    },
    ProviderSpec {
        id: "ollama",
        create: make_ollama,
    },
    ProviderSpec {
        id: "echo",
        create: make_echo,
    },
];

pub fn resolve(config: &LlmConfig) -> Arc<dyn Llm> {
    PROVIDERS
        .iter()
        .find(|spec| spec.id == config.provider)
        .map_or_else(|| make_echo(config), |spec| (spec.create)(config))
}
