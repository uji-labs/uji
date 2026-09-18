use std::rc::Rc;
use std::sync::Arc;

use crate::api::modal::Answer;
use uji_agent::credential;
use uji_agent::llm::Provider;
use uji_ui::app::{Echo, SuggestItem};

use super::{Control, LoopData, ModalInput};
use crate::api::request::Request;
use crate::cmd::{Action, Args, Context};
use crate::runtime::builtin::{self, BUILTINS};
use crate::runtime::events;
use uji_agent::session::store::Setting;

impl LoopData {
    pub(crate) fn refresh_suggestions(&mut self) {
        let pool = suggest_pool(self);
        self.app.set_suggestions(pool);
    }

    pub(super) fn on_command(&mut self, command: &str) {
        let trimmed = command.trim();
        let (name, rest) = match trimmed.find(char::is_whitespace) {
            Some(i) => (&trimmed[..i], trimmed[i..].trim_start()),
            None => (trimmed, ""),
        };
        let args = Args::parse(rest);
        let lua_command = self.inner.api.commands().borrow().get(name).cloned();
        let forced = lua_command.as_ref().is_some_and(|command| command.force);
        let builtin = if forced { None } else { builtin::build(name) };
        if let Some(mut action) = builtin {
            action.start(self, &args);
            self.active = Some(action);
        } else if let Some(command) = lua_command {
            if let Err(err) = command.handler.call::<()>((args.raw.clone(),)) {
                self.inner.report(format!("{name}: {err}"));
            }
        } else {
            self.inner.report(format!("unknown command: {name}"));
        }
    }

    pub(super) fn on_modal(&mut self, input: ModalInput) {
        let Some(mut modal) = self.modal.take() else {
            return;
        };
        match input {
            ModalInput::Select(item) => modal.on_select(self, item),
            ModalInput::Prompt(value) => modal.on_prompt(self, value),
            ModalInput::Cancel => modal.on_cancel(self),
        }
    }

    pub(super) fn on_modal_answer(&mut self, input: ModalInput) {
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

impl LoopData {
    fn ask_ui(
        &self,
        component: &'static str,
        build: impl FnOnce(&mlua::Lua) -> mlua::Result<mlua::Table>,
    ) -> mlua::Result<()> {
        let lua = &self.inner.lua;
        let opts = build(lua)?;
        let api = Rc::clone(&self.inner.api);
        let done = lua.create_function(move |_, choice: Option<String>| {
            api.request(Request::Answer(match component {
                "prompt" => Answer::Prompt(choice),
                _ => Answer::Select(choice),
            }));
            Ok(())
        })?;
        crate::api::modal::ask_ui(lua, component, opts, done)
    }
}

impl Context for LoopData {
    fn open_select(&mut self, title: String, items: Vec<String>) {
        let built = self.ask_ui("select", |lua| {
            let opts = lua.create_table()?;
            opts.set("title", title.clone())?;
            opts.set("items", items.clone())?;
            Ok(opts)
        });
        if let Err(err) = built {
            self.inner.report(format!("uji.ui.select: {err}"));
            self.app.open_select(title, items);
        }
    }

    fn open_prompt(&mut self, title: String, value: String, echo: Echo) {
        let hidden = echo == Echo::Hidden;
        let built = self.ask_ui("prompt", |lua| {
            let opts = lua.create_table()?;
            opts.set("title", title.clone())?;
            opts.set("value", value.clone())?;
            opts.set("hidden", hidden)?;
            Ok(opts)
        });
        if let Err(err) = built {
            self.inner.report(format!("uji.ui.prompt: {err}"));
            self.app.open_prompt(title, value, echo);
        }
    }

    fn set_setting(&mut self, key: &Setting, value: &str) {
        let _ = self.storage.set_setting(key, value);
    }

    fn get_setting(&mut self, key: &Setting) -> Option<String> {
        self.storage.get_setting(key).ok().flatten()
    }

    fn save_credential(&mut self, provider: &str, key: &str) {
        if let Err(err) = credential::set(provider, key) {
            self.inner
                .report(format!("failed to save credential: {err}"));
        }
    }

    fn resolve_llm(&mut self) {
        self.inner.resolve_llm(&mut *self.storage);
        self.inner.emit(events::Event::StatusChanged.name(), &[]);
        self.dirty = true;
    }

    fn reload(&mut self) {
        self.control = Control::Reload;
    }

    fn quit(&mut self) {
        self.control = Control::Quit;
    }

    fn toggle_thinking(&mut self) {
        self.app.toggle_thinking();
        self.dirty = true;
    }

    fn compact(&mut self) -> bool {
        let keep = self.keep_recent_now();
        self.run_compaction(keep)
    }

    fn start_oauth(&mut self, provider_id: &str) {
        let Some(provider) = self
            .inner
            .api
            .providers()
            .borrow()
            .get(provider_id)
            .cloned()
        else {
            self.inner
                .report(format!("unknown provider: {provider_id}"));
            return;
        };
        crate::runtime::auth::start(
            &self.runtime,
            Arc::clone(&self.inner.client),
            &provider,
            self.signals.clone(),
        );
    }

    fn sync_packs(&mut self) {
        crate::pack::update_all(&self.inner.api);
        self.control = Control::Reload;
    }

    fn notify(&mut self, message: &str) {
        self.app
            .overlay_mut()
            .push_notices(vec![message.to_string()]);
        self.dirty = true;
    }

    fn finish(&mut self) {
        self.action_done = true;
    }

    fn providers(&self) -> Vec<Provider> {
        self.inner.api.providers().borrow().all().to_vec()
    }

    fn provider(&self, id: &str) -> Option<Provider> {
        self.inner.api.providers().borrow().get(id).cloned()
    }

    fn provider_by_name(&self, name: &str) -> Option<Provider> {
        self.inner.api.providers().borrow().by_name(name).cloned()
    }

    fn command_names(&self) -> Vec<String> {
        suggest_pool(self)
            .into_iter()
            .map(|item| item.name)
            .collect()
    }
}

fn suggest_pool(data: &LoopData) -> Vec<SuggestItem> {
    let commands = data.inner.api.commands();
    let commands = commands.borrow();
    let mut items: Vec<SuggestItem> = BUILTINS
        .iter()
        .map(|builtin| SuggestItem {
            name: builtin.name.to_string(),
            desc: commands
                .get(builtin.name)
                .filter(|command| command.force)
                .map(|command| command.desc.as_str())
                .filter(|desc| !desc.is_empty())
                .unwrap_or(builtin.desc)
                .to_string(),
        })
        .collect();
    items.extend(
        commands
            .iter()
            .filter(|(name, _)| !BUILTINS.iter().any(|builtin| builtin.name == *name))
            .map(|(name, command)| SuggestItem {
                name: name.clone(),
                desc: if command.desc.is_empty() {
                    "lua command".to_string()
                } else {
                    command.desc.clone()
                },
            }),
    );
    items
}
