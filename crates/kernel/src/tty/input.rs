use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use crossterm::event::{
    Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent, MouseEventKind,
};
use mlua::serde::SerializeOptions;
use mlua::{
    AnyUserData, Function, IntoLuaMulti, LuaSerdeExt, MultiValue, ObjectLike, UserData,
    UserDataMethods,
};
use serde::Serialize;
use tokio::sync::{Mutex, mpsc};

const POLL: Duration = Duration::from_millis(100);

#[derive(Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Incoming {
    Key {
        key: String,
        ctrl: bool,
        alt: bool,
        shift: bool,
        meta: bool,
        repeat: bool,
    },
    Mouse {
        kind: &'static str,
        button: Option<&'static str>,
        row: u16,
        col: u16,
        ctrl: bool,
        alt: bool,
        shift: bool,
    },
    Paste {
        text: String,
    },
    Resize {
        width: u16,
        height: u16,
    },
    Focus {
        focused: bool,
    },
}

fn key_name(code: KeyCode) -> Option<String> {
    let name = match code {
        KeyCode::Char(ch) => return Some(ch.to_string()),
        KeyCode::F(number) => return Some(format!("f{number}")),
        KeyCode::Enter => "enter",
        KeyCode::Esc => "esc",
        KeyCode::Backspace => "backspace",
        KeyCode::Delete => "delete",
        KeyCode::Tab => "tab",
        KeyCode::BackTab => "backtab",
        KeyCode::Left => "left",
        KeyCode::Right => "right",
        KeyCode::Up => "up",
        KeyCode::Down => "down",
        KeyCode::Home => "home",
        KeyCode::End => "end",
        KeyCode::PageUp => "pageup",
        KeyCode::PageDown => "pagedown",
        KeyCode::Insert => "insert",
        _ => return None,
    };
    Some(name.to_string())
}

fn key(key: KeyEvent) -> Option<Incoming> {
    if key.kind == KeyEventKind::Release {
        return None;
    }
    Some(Incoming::Key {
        key: key_name(key.code)?,
        ctrl: key.modifiers.contains(KeyModifiers::CONTROL),
        alt: key.modifiers.contains(KeyModifiers::ALT),
        shift: key.modifiers.contains(KeyModifiers::SHIFT),
        meta: key
            .modifiers
            .intersects(KeyModifiers::SUPER | KeyModifiers::META),
        repeat: key.kind == KeyEventKind::Repeat,
    })
}

fn button(button: MouseButton) -> &'static str {
    match button {
        MouseButton::Left => "left",
        MouseButton::Right => "right",
        MouseButton::Middle => "middle",
    }
}

fn mouse(mouse: MouseEvent) -> Incoming {
    let (kind, pressed) = match mouse.kind {
        MouseEventKind::Down(pressed) => ("down", Some(button(pressed))),
        MouseEventKind::Up(pressed) => ("up", Some(button(pressed))),
        MouseEventKind::Drag(pressed) => ("drag", Some(button(pressed))),
        MouseEventKind::Moved => ("move", None),
        MouseEventKind::ScrollUp => ("scroll_up", None),
        MouseEventKind::ScrollDown => ("scroll_down", None),
        MouseEventKind::ScrollLeft => ("scroll_left", None),
        MouseEventKind::ScrollRight => ("scroll_right", None),
    };
    Incoming::Mouse {
        kind,
        button: pressed,
        row: mouse.row,
        col: mouse.column,
        ctrl: mouse.modifiers.contains(KeyModifiers::CONTROL),
        alt: mouse.modifiers.contains(KeyModifiers::ALT),
        shift: mouse.modifiers.contains(KeyModifiers::SHIFT),
    }
}

fn incoming(event: Event) -> Option<Incoming> {
    match event {
        Event::Key(pressed) => key(pressed),
        Event::Mouse(moved) => Some(mouse(moved)),
        Event::Paste(text) => Some(Incoming::Paste { text }),
        Event::Resize(width, height) => Some(Incoming::Resize { width, height }),
        Event::FocusGained => Some(Incoming::Focus { focused: true }),
        Event::FocusLost => Some(Incoming::Focus { focused: false }),
    }
}

pub(crate) struct Reader {
    running: Arc<AtomicBool>,
}

impl Reader {
    pub(crate) fn spawn(sender: mpsc::UnboundedSender<Event>, paused: Arc<AtomicBool>) -> Self {
        let running = Arc::new(AtomicBool::new(true));
        let alive = Arc::clone(&running);
        std::thread::spawn(move || {
            while alive.load(Ordering::Relaxed) {
                if paused.load(Ordering::Relaxed) {
                    std::thread::sleep(POLL);
                    continue;
                }
                if !crossterm::event::poll(POLL).unwrap_or(false) || paused.load(Ordering::Relaxed)
                {
                    continue;
                }
                let Ok(event) = crossterm::event::read() else {
                    return;
                };
                if sender.send(event).is_err() {
                    return;
                }
            }
        });
        Self { running }
    }

    pub(crate) fn settle() {
        std::thread::sleep(POLL.saturating_add(POLL / 5));
    }
}

impl Drop for Reader {
    fn drop(&mut self) {
        self.running.store(false, Ordering::Relaxed);
    }
}

pub(crate) struct Input {
    events: Mutex<mpsc::UnboundedReceiver<Event>>,
    _reader: Option<Reader>,
}

impl Input {
    pub(crate) fn new(events: mpsc::UnboundedReceiver<Event>, reader: Option<Reader>) -> Self {
        Self {
            events: Mutex::new(events),
            _reader: reader,
        }
    }

    async fn next(&self) -> Option<Incoming> {
        let mut events = self.events.lock().await;
        loop {
            if let Some(found) = incoming(events.recv().await?) {
                return Some(found);
            }
        }
    }
}

impl UserData for Input {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_async_method("event", |lua, input, ()| async move {
            let Some(found) = input.next().await else {
                return Ok(MultiValue::new());
            };
            let options = SerializeOptions::new().serialize_none_to_null(false);
            lua.to_value_with(&found, options)?.into_lua_multi(&lua)
        });
        methods.add_function("events", |_, input: AnyUserData| {
            let event: Function = input.get("event")?;
            Ok((event, input))
        });
    }
}
