use std::collections::HashMap;
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::credential;
use crate::llm::discover;
use crate::session::store::{SessionStorage, Setting};

use super::tuning::{Effort, Retention};
use super::{Anthropic, Gemini, Llm, NotConfigured, OpenAi};

#[derive(Default)]
pub struct LlmConfig {
    pub provider: String,
    pub model: String,
    pub compat: CompatOverrides,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
    pub auth_env: Vec<String>,
    pub oauth: Option<OAuthSession>,
}

#[derive(Clone)]
pub struct OAuthSession {
    pub provider_id: String,
    pub config: crate::auth::OAuthConfig,
    pub tokens: crate::auth::Tokens,
}

impl LlmConfig {
    pub fn for_provider(
        provider_id: String,
        known: Option<&Provider>,
        model: String,
        base_url: Option<String>,
    ) -> Self {
        let catalog_url = known
            .map(|entry| entry.base_url.clone())
            .filter(|url| !url.is_empty());
        Self {
            compat: known.map(|entry| entry.compat).unwrap_or_default(),
            base_url: base_url.filter(|url| !url.is_empty()).or(catalog_url),
            auth_env: known
                .map(|entry| entry.auth_env.clone())
                .unwrap_or_default(),
            oauth: oauth_session(&provider_id, known),
            api_key: credential::get(&provider_id),
            provider: provider_id,
            model,
        }
    }

    pub fn resolve_key(&self) -> Option<String> {
        self.api_key.clone().or_else(|| env_key(&self.auth_env))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Wire {
    #[serde(rename = "openai-chat")]
    OpenAiChat,
    #[serde(rename = "anthropic")]
    Anthropic,
    #[serde(rename = "gemini")]
    Gemini,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Provider {
    pub id: String,
    pub name: String,
    pub wire: Wire,
    pub base_url: String,
    #[serde(default)]
    pub compat: CompatOverrides,
    #[serde(default)]
    pub auth_env: Vec<String>,
    #[serde(default)]
    pub oauth: Option<crate::auth::OAuthConfig>,
    #[serde(default)]
    pub context_window: Option<u64>,
    #[serde(default)]
    pub models: Vec<Model>,
    #[serde(skip)]
    pub origin: Origin,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Origin {
    #[default]
    Builtin,
    Registered,
}

/// Which field an OpenAI-compatible endpoint wants the output limit in.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MaxTokensField {
    #[default]
    MaxTokens,
    MaxCompletionTokens,
    None,
}

/// How an OpenAI-compatible endpoint wants reasoning effort expressed.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ThinkingFormat {
    #[default]
    #[serde(rename = "openai")]
    OpenAi,
    #[serde(rename = "openrouter")]
    OpenRouter,
    #[serde(rename = "deepseek")]
    DeepSeek,
    Zai,
    Qwen,
    None,
}

/// Where an endpoint deviates from the `OpenAI` API it claims to speak.
///
/// Every field has a default guessed from the base url, so a provider only
/// spells out what the guess gets wrong.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Deserialize, Serialize)]
#[serde(default)]
pub struct CompatOverrides {
    pub max_tokens_field: Option<MaxTokensField>,
    pub thinking: Option<ThinkingFormat>,
    pub tool_result_name: Option<bool>,
    pub finish_reason: Option<bool>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Compat {
    pub max_tokens_field: MaxTokensField,
    pub thinking: ThinkingFormat,
    /// Whether a tool result must repeat the tool's name.
    pub tool_result_name: bool,
    /// Whether the endpoint reports why it stopped. When it does not, a stream
    /// that simply ends is taken as finished rather than cut short.
    pub finish_reason: bool,
}

impl Default for Compat {
    fn default() -> Self {
        Self {
            max_tokens_field: MaxTokensField::MaxTokens,
            thinking: ThinkingFormat::OpenAi,
            tool_result_name: false,
            finish_reason: true,
        }
    }
}

impl Compat {
    /// What an endpoint at `base_url` wants, with anything the provider spelled
    /// out taking precedence over the guess.
    pub fn resolve(base_url: &str, overrides: CompatOverrides) -> Self {
        let guess = Self::guess(base_url);
        Self {
            max_tokens_field: overrides.max_tokens_field.unwrap_or(guess.max_tokens_field),
            thinking: overrides.thinking.unwrap_or(guess.thinking),
            tool_result_name: overrides.tool_result_name.unwrap_or(guess.tool_result_name),
            finish_reason: overrides.finish_reason.unwrap_or(guess.finish_reason),
        }
    }

    /// What an endpoint at `base_url` most likely wants.
    pub fn guess(base_url: &str) -> Self {
        let url = base_url.to_ascii_lowercase();
        let has = |needle: &str| url.contains(needle);
        let thinking = if has("openrouter.ai") {
            ThinkingFormat::OpenRouter
        } else if has("deepseek.com") {
            ThinkingFormat::DeepSeek
        } else if has("bigmodel.cn") || has("z.ai") {
            ThinkingFormat::Zai
        } else if has("dashscope") {
            ThinkingFormat::Qwen
        } else {
            ThinkingFormat::OpenAi
        };
        let max_tokens_field = if has("api.openai.com") {
            MaxTokensField::MaxCompletionTokens
        } else {
            MaxTokensField::MaxTokens
        };
        Self {
            max_tokens_field,
            thinking,
            ..Self::default()
        }
    }
}

pub const MAX_RESERVE: u64 = 20_000;

#[derive(Debug, Clone, Deserialize)]
#[serde(from = "ModelSpec")]
pub struct Model {
    pub id: String,
    pub context: Option<u64>,
    pub output: Option<u64>,
    pub reasoning: bool,
    pub cache: bool,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum ModelSpec {
    Id(String),
    Full {
        id: String,
        #[serde(default)]
        context: Option<u64>,
        #[serde(default)]
        output: Option<u64>,
        #[serde(default)]
        reasoning: bool,
        #[serde(default)]
        cache: bool,
    },
}

impl From<ModelSpec> for Model {
    fn from(spec: ModelSpec) -> Self {
        match spec {
            ModelSpec::Id(id) => Self {
                id,
                context: None,
                output: None,
                reasoning: false,
                cache: false,
            },
            ModelSpec::Full {
                id,
                context,
                output,
                reasoning,
                cache,
            } => Self {
                id,
                context,
                output,
                reasoning,
                cache,
            },
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Budget {
    pub window: u64,
    pub reserve: u64,
}

impl Budget {
    pub fn usable(self) -> u64 {
        self.window.saturating_sub(self.reserve)
    }

    pub fn overflows(self, used: u64) -> bool {
        used >= self.usable()
    }
}

impl Provider {
    pub fn default_model(&self) -> &str {
        self.models.first().map_or("", |model| model.id.as_str())
    }

    pub fn model(&self, id: &str) -> Option<&Model> {
        self.models.iter().find(|model| model.id == id)
    }

    pub fn usable_model(&self, stored: Option<String>) -> String {
        let stored = stored.filter(|model| !model.is_empty());
        if self.models.is_empty() {
            return stored.unwrap_or_default();
        }
        stored
            .filter(|model| self.model(model).is_some())
            .unwrap_or_else(|| self.default_model().to_string())
    }

    pub fn reasons(&self, model_id: &str) -> bool {
        self.model(model_id).is_some_and(|model| model.reasoning)
    }

    pub fn caches(&self, model_id: &str) -> bool {
        self.model(model_id).is_some_and(|model| model.cache)
    }

    pub fn budget(&self, model_id: &str) -> Option<Budget> {
        let known = self.model(model_id);
        let window = known
            .and_then(|model| model.context)
            .or(self.context_window)?;
        let reserve = known
            .and_then(|model| model.output)
            .unwrap_or(MAX_RESERVE)
            .min(window / 4);
        Some(Budget { window, reserve })
    }
}

#[derive(Debug, Clone)]
pub struct Catalog {
    providers: Vec<Provider>,
}

impl Default for Catalog {
    fn default() -> Self {
        Self::builtin()
    }
}

impl Catalog {
    pub fn builtin() -> Self {
        let mut providers: Vec<Provider> =
            serde_json::from_str(include_str!("providers.json")).unwrap_or_default();
        let models: HashMap<String, Vec<Model>> =
            serde_json::from_str(include_str!("models.json")).unwrap_or_default();
        for provider in &mut providers {
            if let Some(known) = models.get(&provider.id) {
                provider.models.clone_from(known);
            }
        }
        Self { providers }
    }

    pub fn add(&mut self, mut provider: Provider) {
        provider.origin = Origin::Registered;
        match self
            .providers
            .iter_mut()
            .find(|entry| entry.id == provider.id)
        {
            Some(entry) => *entry = provider,
            None => self.providers.push(provider),
        }
    }

    pub fn remove(&mut self, id: &str) {
        self.providers.retain(|entry| entry.id != id);
    }

    pub fn get(&self, id: &str) -> Option<&Provider> {
        self.providers.iter().find(|entry| entry.id == id)
    }

    pub fn by_name(&self, name: &str) -> Option<&Provider> {
        self.providers.iter().find(|entry| entry.name == name)
    }

    pub fn all(&self) -> &[Provider] {
        &self.providers
    }

    pub fn set_windows(&mut self, id: &str, windows: &[discover::Windows]) -> usize {
        let Some(provider) = self.providers.iter_mut().find(|entry| entry.id == id) else {
            return 0;
        };
        let mut changed = 0;
        for found in windows {
            let Some(model) = provider
                .models
                .iter_mut()
                .find(|model| model.id == found.model)
            else {
                continue;
            };
            if model.context == found.context && model.output == found.output {
                continue;
            }
            model.context = found.context.or(model.context);
            model.output = found.output.or(model.output);
            changed += 1;
        }
        changed
    }
}

fn env_key(names: &[String]) -> Option<String> {
    names
        .iter()
        .filter_map(|name| std::env::var(name).ok())
        .find(|key| !key.is_empty())
}

pub fn authenticated(provider: &Provider) -> bool {
    credential::load(&provider.id).is_some() || env_key(&provider.auth_env).is_some()
}

fn oauth_session(provider_id: &str, known: Option<&Provider>) -> Option<OAuthSession> {
    let config = known?.oauth.clone()?;
    let credential::Credential::OAuth {
        access,
        refresh,
        expires_at,
    } = credential::load(provider_id)?
    else {
        return None;
    };
    Some(OAuthSession {
        provider_id: provider_id.to_string(),
        config,
        tokens: crate::auth::Tokens {
            access,
            refresh,
            expires_at,
        },
    })
}

pub fn resolve(wire: Option<Wire>, config: &LlmConfig) -> Arc<Llm> {
    if config.provider.is_empty() {
        return Arc::new(Llm::NotConfigured(NotConfigured));
    }
    match wire {
        Some(Wire::Anthropic) => Arc::new(Llm::Anthropic(Box::new(Anthropic::new(config)))),
        Some(Wire::Gemini) => Arc::new(Llm::Gemini(Gemini::new(config))),
        Some(Wire::OpenAiChat) | None => Arc::new(Llm::OpenAi(OpenAi::new(config))),
    }
}

pub struct Selection {
    pub llm: Arc<Llm>,
    pub id: String,
    pub name: String,
    pub model: String,
    pub effort: Effort,
    pub cache: Retention,
}

fn setting(storage: &mut dyn SessionStorage, key: &Setting) -> Option<String> {
    storage.get_setting(key).ok().flatten()
}

pub fn resolve_from_storage(storage: &mut dyn SessionStorage, catalog: &Catalog) -> Selection {
    let provider_id = setting(storage, &Setting::Provider).unwrap_or_default();
    let known = catalog.get(&provider_id);
    let stored = setting(storage, &Setting::Model);
    let model = known.map_or_else(
        || stored.clone().unwrap_or_default(),
        |entry| entry.usable_model(stored.clone()),
    );
    let config = LlmConfig::for_provider(
        provider_id.clone(),
        known,
        model.clone(),
        setting(storage, &Setting::BaseUrl),
    );
    let effort = setting(storage, &Setting::Effort)
        .and_then(|name| Effort::parse(&name))
        .filter(|_| known.is_some_and(|entry| entry.reasons(&model)))
        .unwrap_or_default();
    let cache = setting(storage, &Setting::Cache)
        .and_then(|name| Retention::parse(&name))
        .unwrap_or_default();
    let cache = if known.is_some_and(|entry| entry.caches(&model)) {
        cache
    } else {
        Retention::Off
    };
    Selection {
        llm: resolve(known.map(|entry| entry.wire), &config),
        name: known.map_or_else(|| provider_id.clone(), |entry| entry.name.clone()),
        id: provider_id,
        model,
        effort,
        cache,
    }
}
