use std::borrow::Cow;

use mlua::serde::SerializeOptions;
use mlua::{Function, LuaSerdeExt, Table, Value as LuaValue};
use serde::Serialize;
use uji_core::llm::{Retention, ToolSpec, context};
use uji_core::session::id::SessionId;
use uji_core::session::model::Message;
use uji_ui::model::RunState;

use super::LoopData;
use crate::api::agent;
use crate::runtime::events;

const LOOP: &str = "uji.loop";

#[derive(Serialize)]
struct Turn<'a> {
    text: &'a str,
    system: String,
    messages: Vec<Cow<'a, Message>>,
    tools: Vec<ToolSpec>,
    model: &'a str,
    effort: &'static str,
    max_output: u32,
    cache: &'static str,
    session: SessionId,
}

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
        self.inner.emit(&events::MessageSubmitted { text });

        self.append(Message::User {
            text: text.to_string(),
        });
        self.maybe_title(text);

        let (system, context) = self.prompt(text);
        for message in context {
            self.append(message);
        }
        let tools = self.gather_tools();
        self.start_working();
        match self.start_turn(text, system, tools) {
            Ok(cancel) => self.turn.cancel = Some(cancel),
            Err(err) => {
                self.fail_assistant(&format!("{LOOP}: {err}"));
                self.stop_working();
            }
        }
    }

    fn start_turn(
        &self,
        text: &str,
        system: String,
        tools: Vec<ToolSpec>,
    ) -> mlua::Result<Function> {
        let turn = self.encode_turn(text, system, tools)?;
        let host = agent::host(&self.inner.lua, &self.inner.api)?;
        self.inner
            .require::<Table>(LOOP)?
            .get::<Function>("start")?
            .call((turn, host))
    }

    fn encode_turn(
        &self,
        text: &str,
        system: String,
        tools: Vec<ToolSpec>,
    ) -> mlua::Result<LuaValue> {
        let conversation = self.app.messages();
        let messages = context::build(conversation.messages());
        let cache = if self.inner.llm_caches {
            self.inner.api.cache().get()
        } else {
            Retention::Off
        };
        let turn = Turn {
            text,
            system,
            messages,
            tools,
            model: &self.inner.llm_model,
            effort: self.inner.llm_effort.name(),
            max_output: self.max_output(),
            cache: cache.name(),
            session: conversation.info().id,
        };
        let options = SerializeOptions::new()
            .serialize_none_to_null(false)
            .serialize_unit_to_null(false);
        self.inner.lua.to_value_with(&turn, options)
    }

    pub(super) fn start_working(&mut self) {
        self.inner.state().borrow_mut().begin_work();
        self.inner.emit(&events::StatusChanged);
    }

    pub(crate) fn interrupt(&mut self) -> bool {
        if self.cancel_shell() {
            return true;
        }
        let Some(turn) = self.turn.cancel.take() else {
            return false;
        };
        if let Err(err) = turn.call::<()>(()) {
            self.inner.notify(format!("{LOOP}: {err}"));
        }
        self.dirty = true;
        true
    }

    pub(super) fn stop_working(&mut self) {
        self.turn.cancel = None;
        if let Some(awaiting) = self.turn.awaiting.take() {
            self.release(awaiting);
        }
        self.inner.state().borrow_mut().end_work();
        self.inner.emit(&events::StatusChanged);
        self.inner.emit(&events::TurnFinished);
    }
}
