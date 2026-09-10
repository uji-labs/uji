pub mod providers;

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::sync::LazyLock;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use async_trait::async_trait;
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::oneshot;

use crate::credential;
use crate::session::model::{Message, ToolCall};
use crate::session::store::SessionStorage;
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
    pub reasoning_content: Option<String>,
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

const MAX_ERROR_BODY: usize = 2_000;

pub(crate) async fn status_error(response: reqwest::Response) -> LlmError {
    let status = response.status().as_u16();
    let body = response.text().await.unwrap_or_default();
    if status == 401 || status == 403 {
        LlmError::Auth
    } else {
        let body = clip(body.trim(), MAX_ERROR_BODY);
        LlmError::Http(format!("{status}: {body}"))
    }
}

pub(crate) fn clip(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let head: String = text.chars().take(max).collect();
    format!(
        "{head}\n… [truncated, {max} of {} chars shown]",
        text.chars().count()
    )
}

#[derive(Clone, Default)]
pub struct CancelToken(Arc<AtomicBool>);

impl CancelToken {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.0.store(true, Ordering::Relaxed);
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Relaxed)
    }

    async fn cancelled(&self) {
        while !self.is_cancelled() {
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
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
    Allow { arguments: String },
    Deny { reason: String },
}

pub enum StreamEvent {
    Delta(String),
    AssistantStep {
        text: String,
        tool_calls: Vec<ToolCall>,
        reasoning_content: Option<String>,
    },
    ToolResult {
        tool_call_id: String,
        name: String,
        content: String,
    },
    ToolDecisionRequest {
        tool: ToolCall,
        subject: String,
        reply: oneshot::Sender<ToolDecision>,
    },
    RunLuaTool {
        name: String,
        arguments: String,
        reply: oneshot::Sender<String>,
    },
    Done {
        text: String,
        reasoning_content: Option<String>,
    },
    Cancelled,
    Failed(String),
}

pub const DEFAULT_SYSTEM_PROMPT: &str = r"You are uji, a coding agent running in a terminal. You can read and edit files and run shell commands in the working directory.

# Task execution

Keep going until the user's task is completely resolved before ending your turn. Do not stop at analysis or a partial fix: carry the change through to implementation and verification. Persevere when a tool call fails - read the error, adjust, and retry.

Unless the user is clearly asking a question, brainstorming, or explicitly asking for a plan, assume they want you to make the change. Do not describe a patch you could apply - apply it.

Never guess at file contents, APIs, or line numbers. Read the file first. If you are unsure how something works, search for it.

# Using tools

- Every tool call must be a real function call. Never write a tool call as text, as a code block, or as JSON in your reply - text like that is shown to the user and nothing runs.
- Arguments must be a single JSON object matching the tool's schema exactly. Do not wrap them in extra quotes or markdown fences.
- Call one tool at a time and read its result before deciding the next step.
- To change an existing file use `edit_file`. It replaces an exact snippet, so the rest of the file is untouched. Use `write_file` only to create a new file or to rewrite one deliberately from scratch - it overwrites the whole file.
- Before `edit_file`, read the region you are editing so `old_string` matches byte for byte, including indentation. Include enough surrounding context to make the snippet unique.
- Use `grep` to find code by pattern and `list_dir` to explore structure. Prefer these over shelling out to `find`/`grep` through `run_command`.
- `run_command` runs a real shell command in the working directory. Use it to build, test, and inspect - not as a substitute for the file tools.
- Tool output may be truncated. Truncation is always marked; when it matters, narrow the request instead of assuming you saw everything.

# Making changes

- Fix the root cause rather than papering over a symptom.
- Keep changes minimal, focused, and consistent with the surrounding code's style and naming.
- Do not fix unrelated bugs or reformat untouched code. Mention them in your reply instead.
- Do not add comments explaining the change; write code that reads like the code around it.
- Do not create git commits or branches unless asked.
- After editing, verify with the project's own build or tests when they exist.

# Replying

Be concise and factual. State what you changed and where, referencing paths like `src/app.rs:42`. Do not paste back files you just wrote, and do not tell the user to save anything - your edits are already on disk.";

pub fn system_prompt(overridden: Option<&str>, cwd: &str) -> String {
    let base = overridden.unwrap_or(DEFAULT_SYSTEM_PROMPT);
    format!(
        "{base}\n\n# Environment\n\nWorking directory: {cwd}\nOS: {}",
        std::env::consts::OS
    )
}

pub const MAX_TOOL_ITERATIONS: usize = 100;

const TOOL_TIMEOUT: Duration = Duration::from_secs(300);

pub struct AgentConfig<'a> {
    pub client: &'a reqwest::Client,
    pub provider: &'a dyn Llm,
    pub model: String,
    pub system: Option<String>,
    pub tools: &'a ToolRegistry,
    pub lua_tools: &'a [LuaToolSpec],
    pub cwd: &'a Path,
    pub cancel: CancelToken,
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
    let tool_names: Vec<String> = tool_specs.iter().map(|spec| spec.name.clone()).collect();
    for _ in 0..MAX_TOOL_ITERATIONS {
        if config.cancel.is_cancelled() {
            on_event(StreamEvent::Cancelled);
            return;
        }
        let request = LlmRequest {
            model: config.model.clone(),
            system: config.system.clone(),
            messages: messages.clone(),
            tools: tool_specs.clone(),
        };
        let mut on_delta = |delta: String| on_event(StreamEvent::Delta(delta));
        let streaming = config
            .provider
            .stream(config.client, &request, &mut on_delta);
        let response = tokio::select! {
            result = streaming => result,
            () = config.cancel.cancelled() => {
                on_event(StreamEvent::Cancelled);
                return;
            }
        };
        let response = match response {
            Ok(response) => response,
            Err(err) => {
                on_event(StreamEvent::Failed(err.to_string()));
                return;
            }
        };
        let text = response.text;
        let reasoning_content = response.reasoning_content;
        let mut tool_calls = response.tool_calls;
        for call in &mut tool_calls {
            if call.id.trim().is_empty() {
                call.id = format!("call_{}", uuid::Uuid::now_v7().simple());
            }
        }
        if tool_calls.is_empty() {
            on_event(StreamEvent::Done {
                text,
                reasoning_content,
            });
            return;
        }
        on_event(StreamEvent::AssistantStep {
            text: text.clone(),
            tool_calls: tool_calls.clone(),
            reasoning_content: reasoning_content.clone(),
        });
        messages.push(Message::Assistant {
            text,
            tool_calls: tool_calls.clone(),
            reasoning_content,
        });
        for tool_call in &tool_calls {
            let content = if config.cancel.is_cancelled() {
                String::from("error: interrupted by the user before this tool ran")
            } else {
                execute_tool(config, tool_call, &tool_names, on_event).await
            };
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
        if config.cancel.is_cancelled() {
            on_event(StreamEvent::Cancelled);
            return;
        }
    }
    on_event(StreamEvent::Failed(format!(
        "stopped after {MAX_TOOL_ITERATIONS} tool iterations without a final answer"
    )));
}

fn parse_arguments(raw: &str) -> Result<Value, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(Value::Object(serde_json::Map::new()));
    }
    match serde_json::from_str::<Value>(trimmed) {
        Ok(value @ Value::Object(_)) => Ok(value),
        Ok(other) => Err(format!(
            "error: arguments must be a JSON object, got {}. Send a single object matching the tool schema.",
            json_kind(&other)
        )),
        Err(err) => Err(format!(
            "error: arguments are not valid JSON ({err}). Send a single JSON object matching the tool schema, with no markdown fences. Received: {}",
            clip(trimmed, 500)
        )),
    }
}

fn json_kind(value: &Value) -> &'static str {
    match value {
        Value::Null => "null",
        Value::Bool(_) => "a boolean",
        Value::Number(_) => "a number",
        Value::String(_) => "a string",
        Value::Array(_) => "an array",
        Value::Object(_) => "an object",
    }
}

enum Target<'a> {
    Native(&'a Arc<dyn Tool>),
    Lua(&'a LuaToolSpec),
}

fn find_tool<'a>(config: &'a AgentConfig<'_>, name: &str) -> Option<Target<'a>> {
    if let Some(tool) = config.tools.get(name) {
        return Some(Target::Native(tool));
    }
    config
        .lua_tools
        .iter()
        .find(|tool| tool.name == name)
        .map(Target::Lua)
}

async fn execute_tool(
    config: &AgentConfig<'_>,
    tool_call: &ToolCall,
    tool_names: &[String],
    on_event: &mut (dyn FnMut(StreamEvent) + Send),
) -> String {
    let Some(target) = find_tool(config, &tool_call.name) else {
        return format!(
            "error: unknown tool `{}`. Available tools: {}.",
            tool_call.name,
            tool_names.join(", ")
        );
    };
    let args = match parse_arguments(&tool_call.arguments) {
        Ok(args) => args,
        Err(message) => return message,
    };
    let subject = match target {
        Target::Native(tool) => tool.subject(&args),
        Target::Lua(tool) => tool.subject.clone(),
    };
    let (reply, receiver) = oneshot::channel();
    on_event(StreamEvent::ToolDecisionRequest {
        tool: tool_call.clone(),
        subject,
        reply,
    });
    let decision = match tokio::time::timeout(TOOL_TIMEOUT, receiver).await {
        Ok(Ok(decision)) => decision,
        Ok(Err(_)) => return String::from("denied: no decision"),
        Err(_) => return String::from("denied: timed out waiting for confirmation"),
    };
    match decision {
        ToolDecision::Deny { reason } => format!("denied: {reason}"),
        ToolDecision::Allow { arguments } => {
            let args = parse_arguments(&arguments).unwrap_or(args);
            match target {
                Target::Native(tool) => match tool.run(&args, config.cwd).await {
                    Ok(text) => text,
                    Err(err) => format!("error: {err}"),
                },
                Target::Lua(tool) => run_lua_tool(&tool.name, &args, on_event).await,
            }
        }
    }
}

async fn run_lua_tool(
    name: &str,
    args: &Value,
    on_event: &mut (dyn FnMut(StreamEvent) + Send),
) -> String {
    let (reply, receiver) = oneshot::channel();
    on_event(StreamEvent::RunLuaTool {
        name: name.to_string(),
        arguments: args.to_string(),
        reply,
    });
    match tokio::time::timeout(TOOL_TIMEOUT, receiver).await {
        Ok(Ok(result)) => result,
        Ok(Err(_)) => String::from("error: lua tool did not respond"),
        Err(_) => String::from("error: lua tool timed out"),
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
