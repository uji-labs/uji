use std::rc::Rc;

use crossterm::event::Event as TermEvent;
use tui::app::{self, App, KeyAction, SuggestItem};
use uji_cmd::{Args, Context};
use uji_core::credential;
use uji_core::llm::LlmRequest;
use uji_core::session::model::Message;
use uji_core::session::store::SessionStorage;

use super::Inner;
use super::builtin::Builtin;
use super::events;

pub(crate) enum LlmEvent {
    Delta(String),
    Done(String),
    Failed(String),
}

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
    pub(crate) llm_tx: calloop::channel::Sender<LlmEvent>,
    pub(crate) active: Option<Builtin>,
    pub(crate) action_done: bool,
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
                    KeyAction::Selected(item) => self.on_modal(ModalInput::Select(item)),
                    KeyAction::Prompted(value) => self.on_modal(ModalInput::Prompt(value)),
                    KeyAction::Cancel => self.on_modal(ModalInput::Cancel),
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
        let context: Vec<Message> = self
            .app
            .messages()
            .iter()
            .map(|stored| stored.message.clone())
            .collect();
        let sender = self.llm_tx.clone();
        std::thread::spawn(move || {
            let request = LlmRequest {
                model,
                system: None,
                messages: context,
            };
            let result = provider.stream(&request, &mut |delta| {
                let _ = sender.send(LlmEvent::Delta(delta.to_string()));
            });
            let event = match result {
                Ok(text) => LlmEvent::Done(text),
                Err(err) => LlmEvent::Failed(err.to_string()),
            };
            let _ = sender.send(event);
        });
    }

    pub(crate) fn on_llm_event(&mut self, event: LlmEvent) {
        match event {
            LlmEvent::Delta(delta) => {
                self.app.append_pending(&delta);
                self.dirty = true;
            }
            LlmEvent::Done(text) => self.finish_assistant(&text),
            LlmEvent::Failed(err) => {
                self.app.take_pending();
                eprintln!("uji: llm: {err}");
                self.dirty = true;
            }
        }
    }

    fn finish_assistant(&mut self, text: &str) {
        let assistant = Message::Assistant {
            text: text.to_string(),
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

    pub(crate) fn reload(&mut self) {
        self.inner.reload();
        self.refresh_suggestions();
        self.dirty = true;
    }

    pub(crate) fn refresh_suggestions(&mut self) {
        let pool = suggest_pool(self);
        self.app.set_suggestions(pool);
    }

    pub(crate) fn refresh_status(&mut self) {
        let state = self.inner.state.borrow();
        let provider = state.current_provider().unwrap_or("echo").to_string();
        let model = state.current_model().unwrap_or_default().to_string();
        let status = if model.is_empty() {
            provider
        } else {
            format!("{provider}/{model}")
        };
        self.app.set_status(status);
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
        } else if let Some(handler) = self.inner.commands.borrow().get(name).cloned() {
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
        self.refresh_status();
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
        .commands
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
