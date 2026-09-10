use std::collections::HashMap;
use std::rc::Rc;

use mlua::{Function, Lua, Table, Value};

use crate::Api;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Mode {
    Normal,
    Confirm,
    Select,
    Prompt,
    Suggest,
}

impl Mode {
    pub fn parse(name: &str) -> Option<Self> {
        match name {
            "normal" => Some(Self::Normal),
            "confirm" => Some(Self::Confirm),
            "select" => Some(Self::Select),
            "prompt" => Some(Self::Prompt),
            "suggest" => Some(Self::Suggest),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Confirm => "confirm",
            Self::Select => "select",
            Self::Prompt => "prompt",
            Self::Suggest => "suggest",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Key {
    Char(char),
    Enter,
    Escape,
    Backspace,
    Delete,
    Tab,
    BackTab,
    Left,
    Right,
    Up,
    Down,
    Home,
    End,
    PageUp,
    PageDown,
    Insert,
    F(u8),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Chord {
    pub key: Key,
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
}

impl Chord {
    pub fn new(key: Key, ctrl: bool, alt: bool, shift: bool) -> Self {
        let key = match key {
            Key::Char(c) => Key::Char(c.to_ascii_lowercase()),
            other => other,
        };
        let shift = match key {
            Key::Char(_) => false,
            Key::BackTab => true,
            _ => shift,
        };
        Self {
            key,
            ctrl,
            alt,
            shift,
        }
    }

    pub fn parse(spec: &str) -> Option<Self> {
        let spec = spec.trim();
        if spec.is_empty() {
            return None;
        }
        if !(spec.starts_with('<') && spec.ends_with('>')) {
            let mut chars = spec.chars();
            let first = chars.next()?;
            if chars.next().is_some() {
                return None;
            }
            return Some(Self::new(Key::Char(first), false, false, false));
        }
        let mut rest = &spec[1..spec.len() - 1];
        let mut ctrl = false;
        let mut alt = false;
        let mut shift = false;
        while let Some((prefix, tail)) = rest.split_at_checked(2) {
            match prefix.to_ascii_lowercase().as_str() {
                "c-" => ctrl = true,
                "a-" | "m-" => alt = true,
                "s-" if !tail.eq_ignore_ascii_case("tab") => shift = true,
                _ => break,
            }
            rest = tail;
        }
        let key = parse_key(rest)?;
        Some(Self::new(key, ctrl, alt, shift))
    }
}

fn parse_key(name: &str) -> Option<Key> {
    let lowered = name.to_ascii_lowercase();
    let key = match lowered.as_str() {
        "cr" | "enter" | "return" => Key::Enter,
        "esc" | "escape" => Key::Escape,
        "bs" | "backspace" => Key::Backspace,
        "del" | "delete" => Key::Delete,
        "tab" => Key::Tab,
        "s-tab" | "backtab" => Key::BackTab,
        "left" => Key::Left,
        "right" => Key::Right,
        "up" => Key::Up,
        "down" => Key::Down,
        "home" => Key::Home,
        "end" => Key::End,
        "pageup" | "pgup" => Key::PageUp,
        "pagedown" | "pgdn" => Key::PageDown,
        "insert" => Key::Insert,
        "space" => Key::Char(' '),
        "lt" => Key::Char('<'),
        "gt" => Key::Char('>'),
        _ => {
            if let Some(number) = lowered.strip_prefix('f')
                && let Ok(number) = number.parse::<u8>()
                && (1..=12).contains(&number)
            {
                Key::F(number)
            } else {
                let mut chars = name.chars();
                let first = chars.next()?;
                if chars.next().is_some() {
                    return None;
                }
                Key::Char(first)
            }
        }
    };
    Some(key)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Binding {
    Action(String),
    Command(String),
    Unbound,
}

#[derive(Debug, Default)]
pub struct Keymap {
    map: HashMap<(Mode, Chord), Binding>,
}

impl Keymap {
    pub fn set(&mut self, mode: Mode, chord: Chord, binding: Binding) {
        self.map.insert((mode, chord), binding);
    }

    pub fn get(&self, mode: Mode, chord: Chord) -> Option<&Binding> {
        self.map.get(&(mode, chord))
    }

    pub fn clear(&mut self) {
        self.map.clear();
    }

    pub fn entries(&self) -> impl Iterator<Item = (&(Mode, Chord), &Binding)> {
        self.map.iter()
    }
}

fn binding_from_lua(value: &Value) -> Option<Binding> {
    match value {
        Value::Nil => Some(Binding::Unbound),
        Value::String(action) => Some(Binding::Action(action.to_string_lossy())),
        Value::Table(table) => {
            if let Ok(Some(command)) = table.get::<Option<String>>("command") {
                return Some(Binding::Command(command));
            }
            if let Ok(Some(action)) = table.get::<Option<String>>("action") {
                return Some(Binding::Action(action));
            }
            None
        }
        _ => None,
    }
}

fn target(mode: &str, key: &str) -> mlua::Result<(Mode, Chord)> {
    let parsed_mode = Mode::parse(mode)
        .ok_or_else(|| mlua::Error::runtime(format!("unknown keymap mode: {mode}")))?;
    let chord = Chord::parse(key)
        .ok_or_else(|| mlua::Error::runtime(format!("cannot parse key: {key}")))?;
    Ok((parsed_mode, chord))
}

pub(crate) fn set(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let api = Rc::clone(api);
    lua.create_function(move |_, (mode, key, binding): (String, String, Value)| {
        let (mode, chord) = target(&mode, &key)?;
        let binding = binding_from_lua(&binding).ok_or_else(|| {
            mlua::Error::runtime("binding must be an action name, { command = \"...\" }, or nil")
        })?;
        api.keymap().borrow_mut().set(mode, chord, binding);
        Ok(())
    })
}

pub(crate) fn del(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let api = Rc::clone(api);
    lua.create_function(move |_, (mode, key): (String, String)| {
        let (mode, chord) = target(&mode, &key)?;
        api.keymap().borrow_mut().set(mode, chord, Binding::Unbound);
        Ok(())
    })
}

pub(crate) fn reset(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let api = Rc::clone(api);
    lua.create_function(move |_, ()| {
        api.keymap().borrow_mut().clear();
        Ok(())
    })
}

pub(crate) fn list(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let api = Rc::clone(api);
    lua.create_function(move |lua, ()| {
        let out = lua.create_table()?;
        for ((mode, chord), binding) in api.keymap().borrow().entries() {
            let row = lua.create_table()?;
            row.set("mode", mode.name())?;
            row.set("key", describe(*chord))?;
            match binding {
                Binding::Action(name) => row.set("action", name.clone())?,
                Binding::Command(name) => row.set("command", name.clone())?,
                Binding::Unbound => row.set("unbound", true)?,
            }
            out.push(row)?;
        }
        Ok(out)
    })
}

pub fn describe(chord: Chord) -> String {
    let name = match chord.key {
        Key::Char(' ') => String::from("Space"),
        Key::Char(c) => c.to_string(),
        Key::Enter => String::from("CR"),
        Key::Escape => String::from("Esc"),
        Key::Backspace => String::from("BS"),
        Key::Delete => String::from("Del"),
        Key::Tab => String::from("Tab"),
        Key::BackTab => String::from("S-Tab"),
        Key::Left => String::from("Left"),
        Key::Right => String::from("Right"),
        Key::Up => String::from("Up"),
        Key::Down => String::from("Down"),
        Key::Home => String::from("Home"),
        Key::End => String::from("End"),
        Key::PageUp => String::from("PageUp"),
        Key::PageDown => String::from("PageDown"),
        Key::Insert => String::from("Insert"),
        Key::F(number) => format!("F{number}"),
    };
    let bare =
        matches!(chord.key, Key::Char(c) if c != ' ') && !chord.ctrl && !chord.alt && !chord.shift;
    if bare {
        return name;
    }
    let mut out = String::from("<");
    if chord.ctrl {
        out.push_str("C-");
    }
    if chord.alt {
        out.push_str("A-");
    }
    if chord.shift && !matches!(chord.key, Key::BackTab) {
        out.push_str("S-");
    }
    out.push_str(&name);
    out.push('>');
    out
}

pub(crate) fn register(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Table> {
    let keymap = lua.create_table()?;
    keymap.set("set", set(lua, api)?)?;
    keymap.set("del", del(lua, api)?)?;
    keymap.set("reset", reset(lua, api)?)?;
    keymap.set("list", list(lua, api)?)?;
    Ok(keymap)
}
