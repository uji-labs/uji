use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossterm::event::Event as TermEvent;
use uji_api::model::RunState;

use crate::app::{self, App, KeyAction, SuggestItem};
use crate::cmd::{Args, Context};
use crate::credential;
use crate::llm::{AgentConfig, LuaToolSpec, StreamEvent, ToolDecision, ToolSpec, run_agent};
use crate::session::model::{Message, ToolCall};
use crate::session::store::SessionStorage;
use mlua::LuaSerdeExt;

use super::Inner;
use super::builtin::Builtin;
use super::events;

enum ModalInput {
    Select(String),
    Prompt(String),
    Cancel,
}

pub(crate) struct LoopData {
    pub(crate) inner: Rc<Inner>,
    pub(crate) app: App,
    pub(crate) storage: Box<dyn SessionStorage>,
    pub(crate) terminal: app::Term,
    pub(crate) dirty: bool,
    pub(crate) running: bool,
    pub(crate) llm_tx: calloop::channel::Sender<StreamEvent>,
    pub(crate) runtime: tokio::runtime::Runtime,
    pub(crate) active: Option<Builtin>,
    pub(crate) action_done: bool,
    pub(crate) pending_tool: Option<(ToolCall, tokio::sync::oneshot::Sender<ToolDecision>)>,
}

impl LoopData {
    pub(crate) fn on_term_event(&mut self, event: &TermEvent) {
        match event {
            TermEvent::Key(key) => {
                let action = self.app.handle_key(*key);
                match action {
                    KeyAction::Quit => self.running = false,
                    KeyAction::Submit(text) => self.submit(&text),
                    KeyAction::Command(command) => self.on_command(&command),
                    KeyAction::Selected(item) => {
                        if self.pending_tool.is_some() {
                            self.resolve_tool_confirmation(item == "allow");
                        } else {
                            self.on_modal(ModalInput::Select(item));
                        }
                    }
                    KeyAction::Prompted(value) => self.on_modal(ModalInput::Prompt(value)),
                    KeyAction::Cancel => {
                        if self.pending_tool.is_some() {
                            self.resolve_tool_confirmation(false);
                        } else {
                            self.on_modal(ModalInput::Cancel);
                        }
                    }
                    KeyAction::None => {}
                }
                self.dirty = true;
            }
            TermEvent::Resize(..) => self.dirty = true,
            _ => {}
        }
    }

    pub(crate) fn submit(&mut self, text: &str) {
        self.inner
            .emit(events::MESSAGE_SUBMITTED, &[("text", text.to_string())]);

        let user = Message::User {
            text: text.to_string(),
        };
        match self.storage.append_message(&self.app.session().id, user) {
            Ok(stored) => {
                self.app.push_message(stored);
                self.inner.emit(
                    events::MESSAGE_APPENDED,
                    &[("type", "user".into()), ("text", text.to_string())],
                );
            }
            Err(err) => {
                eprintln!("uji: failed to persist message: {err}");
            }
        }

        let provider = self.inner.llm.borrow().clone();
        let model = self.inner.llm_model.borrow().clone();
        let client = Arc::clone(&self.inner.client);
        let context: Vec<Message> = self
            .app
            .messages()
            .iter()
            .map(|stored| stored.message.clone())
            .collect();
        let system = {
            let state_rc = self.inner.state();
            let state = state_rc.borrow();
            crate::llm::system_prompt(
                state.opts().agent_system_prompt.as_deref(),
                &self.app.session().directory,
            )
        };
        let policy = self.inner.policy.borrow().clone();
        let lua_tools = self.gather_lua_tools();
        let cwd = self.app.session().directory.clone();
        let sender = self.llm_tx.clone();
        {
            let state_rc = self.inner.state();
            let mut state = state_rc.borrow_mut();
            state.set_run_state(RunState::Working);
            state.set_turn_started(Some(Instant::now()));
        }
        self.inner.emit("status_changed", &[]);
        self.runtime.spawn(async move {
            let tools = crate::tools::builtin_registry();
            let config = AgentConfig {
                client: &client,
                provider: provider.as_ref(),
                model,
                system: Some(system),
                tools: &tools,
                lua_tools: &lua_tools,
                policy: &policy,
                cwd: std::path::Path::new(&cwd),
            };
            let mut on_event = |event: StreamEvent| {
                let _ = sender.send(event);
            };
            run_agent(&config, context, &mut on_event).await;
        });
    }

    pub(crate) fn on_llm_event(&mut self, event: StreamEvent) {
        match event {
            StreamEvent::Delta(delta) => {
                self.app.append_pending(&delta);
                self.dirty = true;
            }
            StreamEvent::AssistantStep { text, tool_calls } => {
                self.app.take_pending();
                self.persist_assistant_step(text, tool_calls);
            }
            StreamEvent::ToolResult {
                tool_call_id,
                name,
                content,
            } => {
                self.persist_tool_result(tool_call_id, name, content);
            }
            StreamEvent::ToolDecisionRequest { tool, reply } => {
                let body = format!("{} {}", tool.name, tool.arguments);
                self.pending_tool = Some((tool, reply));
                self.app.open_confirm("Allow tool call?".into(), body);
                self.dirty = true;
            }
            StreamEvent::RunLuaTool {
                name,
                arguments,
                reply,
            } => {
                let result = self.run_lua_tool(&name, &arguments);
                let _ = reply.send(result);
                self.dirty = true;
            }
            StreamEvent::Done(text) => {
                self.finish_assistant(&text);
                self.stop_working();
            }
            StreamEvent::Failed(err) => {
                self.app.take_pending();
                self.fail_assistant(&err);
                self.stop_working();
            }
        }
    }

    fn persist_assistant_step(&mut self, text: String, tool_calls: Vec<ToolCall>) {
        if !tool_calls.is_empty() {
            let names = tool_calls
                .iter()
                .map(|call| call.name.as_str())
                .collect::<Vec<_>>()
                .join(",");
            self.inner.emit(events::TOOL_STARTED, &[("tools", names)]);
        }
        let message = Message::Assistant { text, tool_calls };
        match self.storage.append_message(&self.app.session().id, message) {
            Ok(stored) => self.app.push_message(stored),
            Err(err) => eprintln!("uji: failed to persist assistant step: {err}"),
        }
        self.dirty = true;
    }

    fn persist_tool_result(&mut self, tool_call_id: String, name: String, content: String) {
        self.inner.emit(
            events::TOOL_FINISHED,
            &[("name", name.clone()), ("content", content.clone())],
        );
        let message = Message::Tool {
            tool_call_id,
            name,
            content,
        };
        match self.storage.append_message(&self.app.session().id, message) {
            Ok(stored) => self.app.push_message(stored),
            Err(err) => eprintln!("uji: failed to persist tool result: {err}"),
        }
        self.dirty = true;
    }

    fn resolve_tool_confirmation(&mut self, allow: bool) {
        if let Some((_, reply)) = self.pending_tool.take() {
            let decision = if allow {
                ToolDecision::Allow
            } else {
                ToolDecision::Deny {
                    reason: String::from("user denied"),
                }
            };
            let _ = reply.send(decision);
        }
        self.app.close_modal();
        self.dirty = true;
    }

    fn gather_lua_tools(&self) -> Vec<LuaToolSpec> {
        let mut tools = Vec::new();
        for (name, tool) in self.inner.api.lua_tools().borrow().iter() {
            let parameters: serde_json::Value = self
                .inner
                .lua
                .from_value(tool.parameters.clone())
                .unwrap_or(serde_json::Value::Object(serde_json::Map::new()));
            tools.push(LuaToolSpec {
                name: name.clone(),
                spec: ToolSpec {
                    name: name.clone(),
                    description: tool.description.clone(),
                    parameters,
                },
                subject: tool.subject.clone().unwrap_or_else(|| name.clone()),
            });
        }
        tools
    }

    fn run_lua_tool(&self, name: &str, arguments: &str) -> String {
        let args: serde_json::Value =
            serde_json::from_str(arguments).unwrap_or(serde_json::Value::Null);
        let Ok(args) = self.inner.lua.to_value(&args) else {
            return String::from("error: failed to convert arguments");
        };
        let tools = self.inner.api.lua_tools();
        let tools = tools.borrow();
        let Some(tool) = tools.get(name) else {
            return format!("error: unknown tool {name}");
        };
        match tool.run.call::<String>(args) {
            Ok(text) => text,
            Err(err) => format!("error: {err}"),
        }
    }

    fn stop_working(&mut self) {
        {
            let state_rc = self.inner.state();
            let mut state = state_rc.borrow_mut();
            state.set_run_state(RunState::Idle);
            state.set_turn_started(None);
        }
        self.inner.emit("status_changed", &[]);
    }

    fn fail_assistant(&mut self, error: &str) {
        let message = Message::Error {
            text: error.to_string(),
        };
        match self.storage.append_message(&self.app.session().id, message) {
            Ok(stored) => {
                self.app.push_message(stored);
                self.inner.emit(
                    events::MESSAGE_APPENDED,
                    &[("type", "error".into()), ("text", error.to_string())],
                );
            }
            Err(err) => {
                eprintln!("uji: failed to persist error: {err}");
            }
        }
        self.dirty = true;
    }

    fn finish_assistant(&mut self, text: &str) {
        let assistant = Message::Assistant {
            text: text.to_string(),
            tool_calls: Vec::new(),
        };
        match self
            .storage
            .append_message(&self.app.session().id, assistant)
        {
            Ok(stored) => {
                self.app.push_message(stored);
                self.app.take_pending();
                self.inner.emit(
                    events::MESSAGE_APPENDED,
                    &[("type", "assistant".into()), ("text", text.to_string())],
                );
            }
            Err(err) => {
                eprintln!("uji: failed to persist response: {err}");
            }
        }
        self.dirty = true;
    }

    pub(crate) fn refresh_suggestions(&mut self) {
        let pool = suggest_pool(self);
        self.app.set_suggestions(pool);
    }

    pub(crate) fn on_timer(&mut self) {
        let working = self.inner.state().borrow().run_state() == RunState::Working;
        if working {
            self.inner.emit("tick", &[]);
            self.dirty = true;
        }
    }

    pub(crate) fn timer_interval(&self) -> Duration {
        let ms = self.inner.state().borrow().opts().loader_interval_ms.max(1);
        Duration::from_millis(ms)
    }

    fn on_command(&mut self, command: &str) {
        let trimmed = command.trim();
        let (name, rest) = match trimmed.find(char::is_whitespace) {
            Some(i) => (&trimmed[..i], trimmed[i..].trim_start()),
            None => (trimmed, ""),
        };
        let args = Args::parse(rest);
        if let Some(mut action) = Builtin::from_name(name) {
            action.start(self, &args);
            self.active = Some(action);
        } else if let Some(handler) = self.inner.api.commands().borrow().get(name).cloned() {
            if let Err(err) = handler.call::<()>((args.raw.clone(),)) {
                eprintln!("uji: command error: {err}");
            }
        } else {
            eprintln!("uji: unknown command: {name}");
        }
    }

    fn on_modal(&mut self, input: ModalInput) {
        let mut active = self.active.take();
        if let Some(action) = active.as_mut() {
            self.action_done = false;
            match input {
                ModalInput::Select(item) => action.on_select(self, item),
                ModalInput::Prompt(value) => action.on_prompt(self, value),
                ModalInput::Cancel => action.on_cancel(self),
            }
        }
        if let Some(action) = active
            && !self.action_done
        {
            self.active = Some(action);
        }
    }
}

impl Context for LoopData {
    fn open_select(&mut self, title: String, items: Vec<String>) {
        self.app.open_select(title, items);
    }

    fn open_prompt(&mut self, title: String, value: String, secret: bool) {
        self.app.open_prompt(title, value, secret);
    }

    fn set_setting(&mut self, key: &str, value: &str) {
        let _ = self.storage.set_setting(key, value);
    }

    fn get_setting(&mut self, key: &str) -> Option<String> {
        self.storage.get_setting(key).ok().flatten()
    }

    fn save_credential(&mut self, provider: &str, key: &str) {
        if let Err(err) = credential::set(provider, key) {
            eprintln!("uji: failed to save credential: {err}");
        }
    }

    fn resolve_llm(&mut self) {
        self.inner.resolve_llm(&mut *self.storage);
        self.inner.emit("status_changed", &[]);
        self.dirty = true;
    }

    fn reload(&mut self) {
        self.inner.reload();
        self.refresh_suggestions();
        self.dirty = true;
    }

    fn notify(&mut self, message: &str) {
        eprintln!("uji: {message}");
    }

    fn finish(&mut self) {
        self.action_done = true;
    }

    fn command_names(&self) -> Vec<String> {
        suggest_pool(self)
            .into_iter()
            .map(|item| item.name)
            .collect()
    }
}

fn suggest_pool(data: &LoopData) -> Vec<SuggestItem> {
    let mut items: Vec<SuggestItem> = Builtin::ALL
        .iter()
        .map(|(name, desc)| SuggestItem {
            name: (*name).to_string(),
            desc: (*desc).to_string(),
        })
        .collect();
    let mut lua: Vec<SuggestItem> = data
        .inner
        .api
        .commands()
        .borrow()
        .keys()
        .map(|name| SuggestItem {
            name: name.clone(),
            desc: "lua command".into(),
        })
        .collect();
    items.append(&mut lua);
    items
}
