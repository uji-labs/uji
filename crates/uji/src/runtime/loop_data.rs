use std::collections::{HashSet, VecDeque};
use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossterm::event::{Event as TermEvent, KeyCode, KeyEvent, KeyModifiers};
use uji_api::keymap::{Binding, Chord, Key};
use uji_api::model::RunState;

use crate::app::{self, Action as KeyBinding, App, KeyAction, SuggestItem};
use crate::cmd::{Args, Context};
use crate::credential;
use crate::llm::{
    AgentConfig, CancelToken, LuaToolSpec, StreamEvent, ToolDecision, ToolSpec, run_agent,
};
use crate::session::model::{Message, ToolCall};
use crate::session::store::SessionStorage;
use crate::tools::policy::Action;
use mlua::{LuaSerdeExt, Value as LuaValue};

use super::Inner;
use super::builtin::Builtin;
use super::events;

enum ModalInput {
    Select(String),
    Prompt(String),
    Cancel,
}

enum ToolApproval {
    Allow,
    Deny { reason: String },
    Ask { title: Option<String> },
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
    pub(crate) pending_tool: Option<(String, tokio::sync::oneshot::Sender<ToolDecision>)>,
    pub(crate) queued: VecDeque<String>,
    pub(crate) cancel: Option<CancelToken>,
}

impl LoopData {
    pub(crate) fn on_term_event(&mut self, event: &TermEvent) {
        match event {
            TermEvent::Key(key) => {
                let Some(action) = self.dispatch_key(*key) else {
                    self.dirty = true;
                    return;
                };
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
                    KeyAction::Interrupt => {
                        if !self.interrupt() {
                            self.running = false;
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

    fn dispatch_key(&mut self, key: KeyEvent) -> Option<KeyAction> {
        let mode = self.app.keymap_mode();
        let binding = chord_of(key)
            .and_then(|chord| self.inner.api.keymap().borrow().get(mode, chord).cloned());
        match binding {
            Some(Binding::Unbound) => None,
            Some(Binding::Command(command)) => {
                self.on_command(&command);
                None
            }
            Some(Binding::Action(name)) => {
                if let Some(action) = KeyBinding::parse(&name) {
                    Some(self.app.apply(action))
                } else {
                    eprintln!("uji: unknown keymap action: {name}");
                    None
                }
            }
            None => Some(self.app.handle_key(key)),
        }
    }

    pub(crate) fn submit(&mut self, text: &str) {
        if self.inner.state().borrow().run_state() == RunState::Working {
            self.queued.push_back(text.to_string());
            return;
        }
        self.app.reset_scroll();
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
        let context = sanitize_context(&context);
        let system = {
            let state_rc = self.inner.state();
            let state = state_rc.borrow();
            crate::llm::system_prompt(
                state.opts().agent_system_prompt.as_deref(),
                &self.app.session().directory,
            )
        };
        let lua_tools = self.gather_lua_tools();
        let cwd = self.app.session().directory.clone();
        let sender = self.llm_tx.clone();
        let cancel = CancelToken::new();
        self.cancel = Some(cancel.clone());
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
                cwd: std::path::Path::new(&cwd),
                cancel,
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
            StreamEvent::AssistantStep {
                text,
                tool_calls,
                reasoning_content,
            } => {
                self.app.take_pending();
                self.persist_assistant_step(text, tool_calls, reasoning_content);
            }
            StreamEvent::ToolResult {
                tool_call_id,
                name,
                content,
            } => {
                self.persist_tool_result(tool_call_id, name, content);
            }
            StreamEvent::ToolDecisionRequest {
                tool,
                subject,
                reply,
            } => {
                self.handle_tool_decision(&tool, &subject, reply);
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
            StreamEvent::Done {
                text,
                reasoning_content,
            } => {
                self.finish_assistant(&text, reasoning_content);
                self.stop_working();
                self.maybe_submit_queued();
            }
            StreamEvent::Cancelled => {
                self.app.take_pending();
                self.fail_assistant("interrupted");
                self.stop_working();
                self.queued.clear();
            }
            StreamEvent::Failed(err) => {
                self.app.take_pending();
                self.fail_assistant(&err);
                self.stop_working();
                self.maybe_submit_queued();
            }
        }
    }

    pub(crate) fn interrupt(&mut self) -> bool {
        if self.inner.state().borrow().run_state() != RunState::Working {
            return false;
        }
        if let Some(cancel) = &self.cancel {
            cancel.cancel();
        }
        self.dirty = true;
        true
    }

    fn persist_assistant_step(
        &mut self,
        text: String,
        tool_calls: Vec<ToolCall>,
        reasoning_content: Option<String>,
    ) {
        if !tool_calls.is_empty() {
            let names = tool_calls
                .iter()
                .map(|call| call.name.as_str())
                .collect::<Vec<_>>()
                .join(",");
            self.inner.emit(events::TOOL_STARTED, &[("tools", names)]);
        }
        let message = Message::Assistant {
            text,
            tool_calls,
            reasoning_content,
        };
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
        if let Some((arguments, reply)) = self.pending_tool.take() {
            let decision = if allow {
                ToolDecision::Allow { arguments }
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

    fn handle_tool_decision(
        &mut self,
        tool: &ToolCall,
        subject: &str,
        reply: tokio::sync::oneshot::Sender<ToolDecision>,
    ) {
        let args_json: serde_json::Value =
            serde_json::from_str(tool.arguments.as_str()).unwrap_or(serde_json::Value::Null);
        let Ok(args_lua) = self.inner.lua.to_value(&args_json) else {
            let _ = reply.send(ToolDecision::Deny {
                reason: String::from("failed to decode arguments"),
            });
            return;
        };
        let LuaValue::Table(args_table) = args_lua else {
            let _ = reply.send(ToolDecision::Deny {
                reason: String::from("arguments must be an object"),
            });
            return;
        };

        let Ok(event) = self.inner.lua.create_table() else {
            let _ = reply.send(ToolDecision::Deny {
                reason: String::from("failed to build event"),
            });
            return;
        };
        let _ = event.set("name", tool.name.clone());
        let _ = event.set("arguments", args_table.clone());

        let decision = self.inner.api.dispatch_tool("tool_call", &event);
        let approval = if let Some(approval) = parse_tool_decision(decision) {
            approval
        } else {
            let policy = self.inner.policy.borrow();
            match policy.evaluate(tool.name.as_str(), subject) {
                Action::Allow => ToolApproval::Allow,
                Action::Deny => ToolApproval::Deny {
                    reason: String::from("denied by policy"),
                },
                Action::Ask => ToolApproval::Ask { title: None },
            }
        };

        let final_args: serde_json::Value = self
            .inner
            .lua
            .from_value(LuaValue::Table(args_table))
            .unwrap_or(args_json);
        let final_args = final_args.to_string();

        match approval {
            ToolApproval::Allow => {
                let _ = reply.send(ToolDecision::Allow {
                    arguments: final_args,
                });
            }
            ToolApproval::Deny { reason } => {
                let _ = reply.send(ToolDecision::Deny { reason });
            }
            ToolApproval::Ask { title } => {
                let (question, body) = format_tool_call(&tool.name, &final_args);
                let title = title.unwrap_or(question);
                self.pending_tool = Some((final_args, reply));
                self.app.open_confirm(title, body);
                self.dirty = true;
            }
        }
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
        self.cancel = None;
        {
            let state_rc = self.inner.state();
            let mut state = state_rc.borrow_mut();
            state.set_run_state(RunState::Idle);
            state.set_turn_started(None);
        }
        self.inner.emit("status_changed", &[]);
    }

    fn maybe_submit_queued(&mut self) {
        if let Some(text) = self.queued.pop_front() {
            self.submit(&text);
        }
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

    fn finish_assistant(&mut self, text: &str, reasoning_content: Option<String>) {
        let assistant = Message::Assistant {
            text: text.to_string(),
            tool_calls: Vec::new(),
            reasoning_content,
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

fn chord_of(key: KeyEvent) -> Option<Chord> {
    let mapped = match key.code {
        KeyCode::Char(c) => Key::Char(c),
        KeyCode::Enter => Key::Enter,
        KeyCode::Esc => Key::Escape,
        KeyCode::Backspace => Key::Backspace,
        KeyCode::Delete => Key::Delete,
        KeyCode::Tab => Key::Tab,
        KeyCode::BackTab => Key::BackTab,
        KeyCode::Left => Key::Left,
        KeyCode::Right => Key::Right,
        KeyCode::Up => Key::Up,
        KeyCode::Down => Key::Down,
        KeyCode::Home => Key::Home,
        KeyCode::End => Key::End,
        KeyCode::PageUp => Key::PageUp,
        KeyCode::PageDown => Key::PageDown,
        KeyCode::Insert => Key::Insert,
        KeyCode::F(number) => Key::F(number),
        _ => return None,
    };
    Some(Chord::new(
        mapped,
        key.modifiers.contains(KeyModifiers::CONTROL),
        key.modifiers.contains(KeyModifiers::ALT),
        key.modifiers.contains(KeyModifiers::SHIFT),
    ))
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

fn sanitize_context(messages: &[Message]) -> Vec<Message> {
    let mut answered: HashSet<&str> = HashSet::new();
    for message in messages {
        if let Message::Tool { tool_call_id, .. } = message {
            answered.insert(tool_call_id.as_str());
        }
    }

    let mut kept: HashSet<String> = HashSet::new();
    let mut out = Vec::with_capacity(messages.len());
    for message in messages {
        match message {
            Message::Assistant {
                text,
                tool_calls,
                reasoning_content,
            } if !tool_calls.is_empty() => {
                let complete = tool_calls
                    .iter()
                    .all(|call| answered.contains(call.id.as_str()));
                if complete {
                    for call in tool_calls {
                        kept.insert(call.id.clone());
                    }
                    out.push(message.clone());
                } else if !text.is_empty() {
                    out.push(Message::Assistant {
                        text: text.clone(),
                        tool_calls: Vec::new(),
                        reasoning_content: reasoning_content.clone(),
                    });
                }
            }
            Message::Tool { tool_call_id, .. } => {
                if kept.contains(tool_call_id.as_str()) {
                    out.push(message.clone());
                }
            }
            _ => out.push(message.clone()),
        }
    }
    out
}

fn format_tool_call(name: &str, arguments: &str) -> (String, String) {
    let args = serde_json::from_str::<serde_json::Value>(arguments).unwrap_or_default();
    let map = match &args {
        serde_json::Value::Object(map) => map.clone(),
        _ => serde_json::Map::new(),
    };
    let field = |key: &str| {
        map.get(key)
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default()
            .to_string()
    };

    match name {
        "run_command" => (
            "Would you like to run the following command?".into(),
            format!("$ {}", field("command")),
        ),
        "edit_file" => (
            "Would you like to make the following edit?".into(),
            format!("Destination: {}", field("path")),
        ),
        "write_file" => (
            "Would you like to write the following file?".into(),
            format!("Destination: {}", field("path")),
        ),
        "read_file" | "list_dir" => (
            format!("Would you like to allow uji to `{name}`?"),
            format!("Path: {}", field("path")),
        ),
        "grep" => (
            "Would you like to allow uji to search the workspace?".into(),
            format!("Pattern: {}", field("pattern")),
        ),
        _ => {
            let detail = if map.is_empty() {
                arguments.to_string()
            } else {
                map.iter()
                    .map(|(key, value)| {
                        let value = value
                            .as_str()
                            .map_or_else(|| value.to_string(), str::to_string);
                        format!("{key}: {value}")
                    })
                    .collect::<Vec<_>>()
                    .join("\n")
            };
            (format!("Would you like to run `{name}`?"), detail)
        }
    }
}

fn parse_tool_decision(value: Option<LuaValue>) -> Option<ToolApproval> {
    let value = value?;
    let LuaValue::Table(table) = value else {
        return None;
    };
    if let Ok(Some(reason)) = table.get::<Option<String>>("deny") {
        return Some(ToolApproval::Deny { reason });
    }
    if let Ok(true) = table.get::<bool>("allow") {
        return Some(ToolApproval::Allow);
    }
    if let Ok(Some(title)) = table.get::<Option<String>>("ask") {
        return Some(ToolApproval::Ask { title: Some(title) });
    }
    if let Ok(true) = table.get::<bool>("ask") {
        return Some(ToolApproval::Ask { title: None });
    }
    None
}
