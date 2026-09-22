use std::sync::Arc;
use std::time::Instant;

use mlua::Value as LuaValue;

use uji_agent::llm::{AgentConfig, CancelToken, StreamEvent, run_agent};
use uji_agent::session::model::Message;
use uji_ui::model::RunState;

use super::LoopData;
use crate::runtime::events;
use crate::runtime::signal::Signal;

impl LoopData {
    pub(crate) fn submit(&mut self, text: &str) {
        if self.inner.state().borrow().run_state() == RunState::Working {
            self.enqueue(text);
            return;
        }
        if self.compact_if_needed() {
            self.enqueue(text);
            return;
        }
        self.app.overlay_mut().clear_notices();
        self.app.reset_scroll();
        self.inner.emit(
            events::Event::MessageSubmitted.name(),
            &[("text", text.to_string())],
        );

        self.append(Message::User {
            text: text.to_string(),
        });
        self.maybe_title(text);

        let provider = self.inner.llm.borrow().clone();
        let model = self.inner.llm_model.borrow().clone();
        let client = Arc::clone(&self.inner.client);
        let context = {
            let conversation = self.app.messages();
            uji_agent::llm::context::build(conversation.messages())
        };

        let system = {
            let state_rc = self.inner.state();
            let state = state_rc.borrow();
            uji_agent::llm::system_prompt(
                state.opts().agent_system_prompt.as_deref(),
                &self.app.session().directory,
            )
        };
        let mut system = system;
        let mut context = context;
        self.gather_context(&mut system, &mut context);
        let lua_tools = self.gather_lua_tools();
        let disabled = self.inner.api.access().borrow().disabled().clone();
        let roots = {
            let access = self.inner.api.access().borrow();
            let extra = access.roots().to_vec();
            if access.confined() {
                uji_agent::tools::builtin::Roots::confined(extra)
            } else {
                uji_agent::tools::builtin::Roots::new(extra)
            }
        };
        let cwd = self.app.session().directory.clone();
        let sender = self.signals.clone();
        let cancel = CancelToken::new();
        self.cancel = Some(cancel.clone());
        let budget = self.budget();
        let keep_recent = self.keep_recent();
        let effort = *self.inner.llm_effort.borrow();
        let cache = *self.inner.llm_cache.borrow();
        let max_output = self.max_output();
        {
            let state_rc = self.inner.state();
            let mut state = state_rc.borrow_mut();
            state.set_run_state(RunState::Working);
            state.set_turn_started(Some(Instant::now()));
        }
        self.inner.emit(events::Event::StatusChanged.name(), &[]);
        self.runtime.spawn(async move {
            let mut tools = uji_agent::tools::builtin_registry(roots);
            tools.disable(&disabled);
            let config = AgentConfig {
                client: &client,
                provider: provider.as_ref(),
                model,
                system: Some(system),
                tools: &tools,
                lua_tools: &lua_tools,
                cwd: std::path::Path::new(&cwd),
                cancel,
                budget,
                keep_recent,
                effort,
                max_output,
                cache,
            };
            let mut on_event = |event: StreamEvent| {
                let _ = sender.send(Signal::Llm(event));
            };
            run_agent(&config, context, &mut on_event).await;
        });
    }

    pub(crate) fn interrupt(&mut self) -> bool {
        if self.cancel_shell() {
            return true;
        }
        let Some(cancel) = self.cancel.take() else {
            return false;
        };
        cancel.cancel();
        self.dirty = true;
        true
    }

    fn gather_context(&self, system: &mut String, messages: &mut Vec<Message>) {
        for (name, call) in self.inner.api.agent_context().borrow().calls() {
            let (text, at_turn) = match call.call::<LuaValue>(()) {
                Ok(LuaValue::String(text)) => (text.to_string_lossy(), false),
                Ok(LuaValue::Table(table)) => {
                    let text = table.get::<Option<String>>("text").unwrap_or_default();
                    let at = table.get::<Option<String>>("at").unwrap_or_default();
                    (text.unwrap_or_default(), at.as_deref() == Some("turn"))
                }
                Ok(_) => continue,
                Err(err) => {
                    self.inner.report(format!("agent context {name}: {err}"));
                    continue;
                }
            };
            if text.trim().is_empty() {
                continue;
            }
            if at_turn {
                messages.push(Message::User { text });
            } else {
                system.push_str("\n\n");
                system.push_str(&text);
            }
        }
    }

    pub(super) fn stop_working(&mut self) {
        self.cancel = None;
        self.awaiting = None;
        {
            let state_rc = self.inner.state();
            let mut state = state_rc.borrow_mut();
            state.set_run_state(RunState::Idle);
            state.set_turn_started(None);
        }
        self.inner.emit(events::Event::StatusChanged.name(), &[]);
        self.inner.emit(events::Event::TurnFinished.name(), &[]);
    }
}
