pub mod providers;

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::sync::LazyLock;
use std::time::Duration;

use async_trait::async_trait;
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::oneshot;

use crate::credential;
use crate::session::model::{Message, ToolCall};
use crate::session::store::SessionStorage;
use crate::tools::policy::{Action, ToolPolicy};
use crate::tools::{Tool, ToolRegistry};

pub use providers::anthropic::Anthropic;
pub use providers::google::Gemini;
pub use providers::not_configured::NotConfigured;
pub use providers::ollama::Ollama;
pub use providers::openai::OpenAi;

pub enum Auth {
    None,
    Bearer { token: String },
    ApiKey { header: String, key: String },
}

impl Auth {
    pub(crate) fn apply(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
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
    pub tools: Vec<ToolSpec>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: Value,
}

#[derive(Debug, Clone)]
pub struct LlmResponse {
    pub text: String,
    pub tool_calls: Vec<ToolCall>,
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

pub(crate) async fn status_error(response: reqwest::Response) -> LlmError {
    let status = response.status().as_u16();
    let body = response.text().await.unwrap_or_default();
    if status == 401 || status == 403 {
        LlmError::Auth
    } else {
        LlmError::Http(format!("{status}: {body}"))
    }
}

#[async_trait]
pub trait Llm: Send + Sync {
    fn id(&self) -> &'static str;
    async fn send_request(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
    ) -> Result<LlmResponse, LlmError>;
    async fn stream(
        &self,
        client: &reqwest::Client,
        request: &LlmRequest,
        on_delta: &mut (dyn FnMut(String) + Send),
    ) -> Result<LlmResponse, LlmError> {
        let response = self.send_request(client, request).await?;
        on_delta(response.text.clone());
        Ok(response)
    }
}

#[derive(Default)]
pub struct LlmConfig {
    pub provider: String,
    pub model: String,
    pub base_url: Option<String>,
    pub api_key: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Wire {
    #[serde(rename = "openai-chat")]
    OpenAiChat,
    #[serde(rename = "anthropic")]
    Anthropic,
    #[serde(rename = "gemini")]
    Gemini,
    #[serde(rename = "ollama")]
    OllamaNative,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Provider {
    pub id: String,
    pub name: String,
    pub wire: Wire,
    pub base_url: String,
    pub auth_env: Option<String>,
}

impl Provider {
    pub fn default_model(&self) -> &'static str {
        models(&self.id).first().copied().unwrap_or("")
    }
}

static PROVIDERS: LazyLock<Vec<Provider>> =
    LazyLock::new(|| serde_json::from_str(include_str!("providers.json")).unwrap_or_default());

pub fn providers() -> &'static [Provider] {
    PROVIDERS.as_slice()
}

pub fn provider(id: &str) -> Option<&'static Provider> {
    PROVIDERS.iter().find(|p| p.id == id)
}

pub fn provider_by_name(name: &str) -> Option<&'static Provider> {
    PROVIDERS.iter().find(|p| p.name == name)
}

static MODELS: LazyLock<HashMap<&'static str, Vec<&'static str>>> =
    LazyLock::new(|| serde_json::from_str(include_str!("models.json")).unwrap_or_default());

pub fn models(id: &str) -> &'static [&'static str] {
    MODELS.get(id).map_or(&[], Vec::as_slice)
}

pub fn resolve(config: &LlmConfig) -> Arc<dyn Llm> {
    if config.provider.is_empty() {
        return Arc::new(NotConfigured);
    }
    let Some(provider) = provider(&config.provider) else {
        return Arc::new(OpenAi::new(config));
    };
    if provider.id == "custom" {
        return Arc::new(OpenAi::new(config));
    }
    let resolved = LlmConfig {
        provider: config.provider.clone(),
        model: config.model.clone(),
        base_url: Some(provider.base_url.clone()),
        api_key: config.api_key.clone(),
    };
    match provider.wire {
        Wire::OpenAiChat => Arc::new(OpenAi::new(&resolved)),
        Wire::Anthropic => Arc::new(Anthropic::new(&resolved)),
        Wire::Gemini => Arc::new(Gemini::new(&resolved)),
        Wire::OllamaNative => Arc::new(Ollama::new(&resolved)),
    }
}

pub enum ToolDecision {
    Allow,
    Deny { reason: String },
}

pub enum StreamEvent {
    Delta(String),
    AssistantStep {
        text: String,
        tool_calls: Vec<ToolCall>,
    },
    ToolResult {
        tool_call_id: String,
        name: String,
        content: String,
    },
    ToolDecisionRequest {
        tool: ToolCall,
        reply: oneshot::Sender<ToolDecision>,
    },
    RunLuaTool {
        name: String,
        arguments: String,
        reply: oneshot::Sender<String>,
    },
    Done(String),
    Failed(String),
}

pub const DEFAULT_SYSTEM_PROMPT: &str = "You are uji, a coding agent running in a terminal. You can inspect and modify files and run shell commands in the working directory. Prefer concrete changes over explanations. When you need to understand the codebase, look at the files first.";

pub fn system_prompt(overridden: Option<&str>, cwd: &str) -> String {
    let base = overridden.unwrap_or(DEFAULT_SYSTEM_PROMPT);
    format!(
        "{base}\n\nWorking directory: {cwd}\nOS: {}",
        std::env::consts::OS
    )
}

const MAX_ITERATIONS: usize = 25;

pub struct AgentConfig<'a> {
    pub client: &'a reqwest::Client,
    pub provider: &'a dyn Llm,
    pub model: String,
    pub system: Option<String>,
    pub tools: &'a ToolRegistry,
    pub lua_tools: &'a [LuaToolSpec],
    pub policy: &'a ToolPolicy,
    pub cwd: &'a Path,
}

#[derive(Clone)]
pub struct LuaToolSpec {
    pub name: String,
    pub spec: ToolSpec,
    pub subject: String,
}

pub async fn run_agent(
    config: &AgentConfig<'_>,
    mut messages: Vec<Message>,
    on_event: &mut (dyn FnMut(StreamEvent) + Send),
) {
    let mut tool_specs = config.tools.specs();
    tool_specs.extend(config.lua_tools.iter().map(|tool| tool.spec.clone()));
    for _ in 0..MAX_ITERATIONS {
        let request = LlmRequest {
            model: config.model.clone(),
            system: config.system.clone(),
            messages: messages.clone(),
            tools: tool_specs.clone(),
        };
        let response = config
            .provider
            .stream(config.client, &request, &mut |delta| {
                on_event(StreamEvent::Delta(delta));
            })
            .await;
        let response = match response {
            Ok(response) => response,
            Err(err) => {
                on_event(StreamEvent::Failed(err.to_string()));
                return;
            }
        };
        let text = response.text;
        let tool_calls = response.tool_calls;
        if tool_calls.is_empty() {
            on_event(StreamEvent::Done(text));
            return;
        }
        on_event(StreamEvent::AssistantStep {
            text: text.clone(),
            tool_calls: tool_calls.clone(),
        });
        messages.push(Message::Assistant {
            text,
            tool_calls: tool_calls.clone(),
        });
        for tool_call in &tool_calls {
            let content = execute_tool(
                tool_call,
                config.tools,
                config.lua_tools,
                config.policy,
                config.cwd,
                on_event,
            )
            .await;
            on_event(StreamEvent::ToolResult {
                tool_call_id: tool_call.id.clone(),
                name: tool_call.name.clone(),
                content: content.clone(),
            });
            messages.push(Message::Tool {
                tool_call_id: tool_call.id.clone(),
                name: tool_call.name.clone(),
                content,
            });
        }
    }
    on_event(StreamEvent::Failed("too many tool iterations".into()));
}

async fn execute_tool(
    tool_call: &ToolCall,
    tools: &ToolRegistry,
    lua_tools: &[LuaToolSpec],
    policy: &ToolPolicy,
    cwd: &Path,
    on_event: &mut (dyn FnMut(StreamEvent) + Send),
) -> String {
    let args: Value = serde_json::from_str(&tool_call.arguments).unwrap_or(Value::Null);
    let subject = match tools.get(&tool_call.name) {
        Some(tool) => tool.subject(&args),
        None => match lua_tools.iter().find(|tool| tool.name == tool_call.name) {
            Some(tool) => tool.subject.clone(),
            None => return format!("unknown tool: {}", tool_call.name),
        },
    };
    match policy.evaluate(&tool_call.name, &subject) {
        Action::Allow => {
            run_named_tool(&tool_call.name, &args, tools, lua_tools, cwd, on_event).await
        }
        Action::Deny => String::from("denied by policy"),
        Action::Ask => {
            let (reply, receiver) = oneshot::channel();
            on_event(StreamEvent::ToolDecisionRequest {
                tool: tool_call.clone(),
                reply,
            });
            match tokio::time::timeout(Duration::from_secs(300), receiver).await {
                Ok(Ok(ToolDecision::Allow)) => {
                    run_named_tool(&tool_call.name, &args, tools, lua_tools, cwd, on_event).await
                }
                Ok(Ok(ToolDecision::Deny { reason })) => format!("denied: {reason}"),
                Ok(Err(_)) => String::from("denied: no decision"),
                Err(_) => String::from("denied: timed out waiting for confirmation"),
            }
        }
    }
}

async fn run_named_tool(
    name: &str,
    args: &Value,
    tools: &ToolRegistry,
    lua_tools: &[LuaToolSpec],
    cwd: &Path,
    on_event: &mut (dyn FnMut(StreamEvent) + Send),
) -> String {
    if let Some(tool) = tools.get(name) {
        return run_tool(tool, args, cwd).await;
    }
    if lua_tools.iter().any(|tool| tool.name == name) {
        let (reply, receiver) = oneshot::channel();
        on_event(StreamEvent::RunLuaTool {
            name: name.to_string(),
            arguments: args.to_string(),
            reply,
        });
        return match tokio::time::timeout(Duration::from_secs(300), receiver).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => String::from("error: lua tool did not respond"),
            Err(_) => String::from("error: lua tool timed out"),
        };
    }
    format!("unknown tool: {name}")
}

async fn run_tool(tool: &Arc<dyn Tool>, args: &Value, cwd: &Path) -> String {
    match tool.run(args, cwd).await {
        Ok(text) => text,
        Err(err) => format!("error: {err}"),
    }
}

pub(crate) async fn response_lines(
    response: reqwest::Response,
    mut on_line: impl FnMut(&str) + Send,
) -> Result<(), LlmError> {
    let mut buf = String::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|err| LlmError::Http(err.to_string()))?;
        buf.push_str(&String::from_utf8_lossy(&chunk));
        while let Some(pos) = buf.find('\n') {
            let line = buf[..pos].trim_end_matches('\r').to_string();
            buf.drain(..=pos);
            on_line(&line);
        }
    }
    Ok(())
}

pub fn resolve_from_storage(storage: &mut dyn SessionStorage) -> (Arc<dyn Llm>, String, String) {
    let provider_id = storage
        .get_setting("llm.provider")
        .ok()
        .flatten()
        .unwrap_or_default();
    let model = storage
        .get_setting("llm.model")
        .ok()
        .flatten()
        .unwrap_or_else(|| {
            provider(&provider_id).map_or_else(String::new, |p| p.default_model().to_string())
        });
    let base_url = storage.get_setting("llm.base_url").ok().flatten();
    let api_key = credential::get(&provider_id);
    let config = LlmConfig {
        provider: provider_id.clone(),
        model: model.clone(),
        base_url,
        api_key,
    };
    (resolve(&config), model, provider_id)
}
