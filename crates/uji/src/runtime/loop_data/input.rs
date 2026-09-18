use uji_ui::app::{Action, KeyAction};
use uji_ui::input::Input;
use uji_ui::keymap::{Binding, Chord, Key, describe};

use super::{Control, LoopData, ModalInput};

impl LoopData {
    pub(crate) fn on_input(&mut self, input: &Input) {
        match input {
            Input::Key(chord) => self.on_key(*chord),
            Input::Mouse { point, kind } => self.on_mouse(*point, *kind),
            Input::Paste(text) => {
                self.app.paste(text);
                self.dirty = true;
            }
            Input::Resize => self.dirty = true,
        }
    }

    fn on_key(&mut self, key: Chord) {
        self.clear_selection();
        let Some(action) = self.dispatch_key(key) else {
            self.dirty = true;
            return;
        };
        match action {
            KeyAction::Quit => self.control = Control::Quit,
            KeyAction::Submit(text) => self.submit(&text),
            KeyAction::Command(command) => self.on_command(&command),
            KeyAction::Shell(command) => self.run_shell(&command),
            KeyAction::Confirmed(allow) => self.resolve_tool_confirmation(allow),
            KeyAction::Selected(item) => self.on_modal(ModalInput::Select(item)),
            KeyAction::Prompted(value) => self.on_modal(ModalInput::Prompt(value)),
            KeyAction::Cancel => self.on_modal(ModalInput::Cancel),
            KeyAction::Interrupt => {
                self.interrupt();
            }
            KeyAction::InterruptOrQuit => {
                if !self.interrupt() {
                    self.control = Control::Quit;
                }
            }
            KeyAction::None => {}
        }
        self.dirty = true;
    }

    fn dispatch_key(&mut self, key: Chord) -> Option<KeyAction> {
        if self.inner.api.capture().is_active() {
            self.dispatch_capture(key);
            return None;
        }
        let mode = self.app.keymap_mode();
        let binding = self.inner.api.keymap().borrow().get(mode, key).cloned();
        match binding {
            Some(Binding::Unbound) => None,
            Some(Binding::Command(command)) => {
                self.on_command(&command);
                None
            }
            Some(Binding::Action(name)) => {
                if let Some(action) = Action::parse(&name) {
                    return Some(self.app.apply(action));
                }
                match self.inner.api.actions().get(&name) {
                    Some(handler) => {
                        if let Err(err) = handler.call::<()>(()) {
                            self.inner.report(format!("action {name}: {err}"));
                        }
                        self.dirty = true;
                    }
                    None => self.inner.report(format!("unknown keymap action: {name}")),
                }
                None
            }
            None => Some(self.app.handle_key(key)),
        }
    }

    fn dispatch_capture(&mut self, chord: Chord) {
        let Some(handler) = self.inner.api.capture().handler() else {
            return;
        };
        let Ok(event) = self.inner.lua.create_table() else {
            return;
        };
        let _ = event.set("key", describe(chord));
        if let Key::Char(c) = chord.key {
            let _ = event.set("char", c.to_string());
        }
        let _ = event.set("ctrl", chord.ctrl);
        let _ = event.set("alt", chord.alt);
        let _ = event.set("shift", chord.shift);
        if let Err(err) = handler.call::<()>((event,)) {
            self.inner.report(format!("capture handler: {err}"));
            self.inner.api.capture().clear();
        }
        self.dirty = true;
    }
}
