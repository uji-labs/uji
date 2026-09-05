use std::rc::Rc;

use crossterm::event::Event as TermEvent;
use tui::app::{self, App, KeyAction};
use uji_core::llm::LlmRequest;
use uji_core::session::model::Message;
use uji_core::session::store::SessionStorage;

use super::Inner;
use super::events;

pub(crate) enum LlmEvent {
    Delta(String),
    Done(String),
    Failed(String),
}

pub(crate) struct LoopData {
    pub(crate) inner: Rc<Inner>,
    pub(crate) app: App,
    pub(crate) storage: Box<dyn SessionStorage>,
    pub(crate) terminal: app::Term,
    pub(crate) dirty: bool,
    pub(crate) running: bool,
    pub(crate) llm_tx: calloop::channel::Sender<LlmEvent>,
}

impl LoopData {
    pub(crate) fn on_term_event(&mut self, event: &TermEvent) {
        match event {
            TermEvent::Key(key) => {
                match self.app.handle_key(*key) {
                    KeyAction::Quit => self.running = false,
                    KeyAction::Submit(text) => self.submit(&text),
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
        self.dirty = true;
    }
}
