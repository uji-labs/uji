use mlua::{Function, Table, Value as LuaValue};
use uji_core::session::model::Message;

use super::LoopData;
use crate::runtime::events;

const PROMPT: &str = "uji.prompt";

impl LoopData {
    pub(super) fn prompt(&self, text: &str) -> (String, Vec<Message>) {
        let mut system = self.base_prompt().unwrap_or_else(|err| {
            self.inner.notify(format!("{PROMPT}: {err}"));
            String::new()
        });
        let at_turn = self.gather_context(&mut system);
        (self.before_turn(system, text), at_turn)
    }

    fn base_prompt(&self) -> mlua::Result<String> {
        let env = self.inner.lua.create_table()?;
        env.set("directory", self.app.messages().info().directory.as_str())?;
        env.set("os", std::env::consts::OS)?;
        self.inner
            .require::<Table>(PROMPT)?
            .get::<Function>("system")?
            .call(env)
    }

    fn gather_context(&self, system: &mut String) -> Vec<Message> {
        let mut messages = Vec::new();
        let calls = self.inner.api.context().borrow().calls();
        for (name, call) in calls {
            let (text, at_turn) = match call.call::<LuaValue>(()) {
                Ok(LuaValue::String(text)) => (text.to_string_lossy(), false),
                Ok(LuaValue::Table(table)) => {
                    let text = table.get::<Option<String>>("text").unwrap_or_default();
                    let at = table.get::<Option<String>>("at").unwrap_or_default();
                    (text.unwrap_or_default(), at.as_deref() == Some("turn"))
                }
                Ok(_) => continue,
                Err(err) => {
                    self.inner.notify(format!("context {name}: {err}"));
                    continue;
                }
            };
            if text.trim().is_empty() {
                continue;
            }
            if at_turn {
                messages.push(Message::Context { text });
            } else {
                system.push_str("\n\n");
                system.push_str(&text);
            }
        }
        messages
    }

    fn before_turn(&self, system: String, text: &str) -> String {
        self.inner.fold(&events::BeforeTurn { text }, system)
    }
}
