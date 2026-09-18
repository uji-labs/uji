use std::collections::HashMap;
use std::str::FromStr;

use strum::{EnumString, IntoStaticStr, VariantArray};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, EnumString, IntoStaticStr, VariantArray)]
#[strum(serialize_all = "snake_case")]
pub enum Mode {
    Normal,
    Confirm,
    Select,
    Prompt,
    Suggest,
}

impl Mode {
    pub fn parse(name: &str) -> Option<Self> {
        Self::from_str(name).ok()
    }

    pub fn name(self) -> &'static str {
        self.into()
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
    pub const fn plain(key: Key) -> Self {
        Self::new(key, false, false, false)
    }

    pub const fn ctrl(key: Key) -> Self {
        Self::new(key, true, false, false)
    }

    pub const fn alt(key: Key) -> Self {
        Self::new(key, false, true, false)
    }

    pub const fn shift(key: Key) -> Self {
        Self::new(key, false, false, true)
    }

    pub const fn new(key: Key, ctrl: bool, alt: bool, shift: bool) -> Self {
        let shift = match key {
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

    /// The form bindings are keyed by.
    ///
    /// A binding names a key, not a character: `<C-a>` and `<C-A>` are the same
    /// chord. The pressed character is kept on the chord itself, because that is
    /// what gets typed into the input.
    fn normalised(self) -> Self {
        match self.key {
            Key::Char(c) => Self {
                key: Key::Char(c.to_ascii_lowercase()),
                shift: false,
                ..self
            },
            _ => self,
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
            return Some(Self::plain(Key::Char(first)));
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

/// Every mode.
const ALL: &[Mode] = &[
    Mode::Normal,
    Mode::Confirm,
    Mode::Select,
    Mode::Prompt,
    Mode::Suggest,
];
/// The modes with a line to edit: the composer, a prompt's value, a picker's
/// query. Confirm has no text, so it is left out.
const EDIT: &[Mode] = &[Mode::Normal, Mode::Suggest, Mode::Prompt, Mode::Select];
/// The modes showing a list to walk.
const LIST: &[Mode] = &[Mode::Select, Mode::Suggest, Mode::Confirm];
/// Only the composer: a prompt and a query are one line by definition.
const COMPOSE: &[Mode] = &[Mode::Normal];

/// The bindings every session starts with.
///
/// These are readline's, because that is what a terminal input is expected to
/// answer to. They are ordinary bindings, so `uji.keymap.set` overrides any of
/// them and `uji.keymap.del` takes one away.
const DEFAULTS: &[(&[Mode], Chord, &str)] = &[
    (ALL, Chord::ctrl(Key::Char('c')), "quit"),
    (EDIT, Chord::ctrl(Key::Char('a')), "cursor_start"),
    (EDIT, Chord::ctrl(Key::Char('e')), "cursor_end"),
    (EDIT, Chord::ctrl(Key::Char('b')), "cursor_left"),
    (EDIT, Chord::ctrl(Key::Char('f')), "cursor_right"),
    (EDIT, Chord::alt(Key::Char('b')), "word_left"),
    (EDIT, Chord::alt(Key::Char('f')), "word_right"),
    (EDIT, Chord::ctrl(Key::Char('h')), "backspace"),
    (EDIT, Chord::ctrl(Key::Char('d')), "delete_forward"),
    (EDIT, Chord::ctrl(Key::Char('w')), "delete_word_back"),
    (EDIT, Chord::alt(Key::Backspace), "delete_word_back"),
    (EDIT, Chord::alt(Key::Char('d')), "delete_word_forward"),
    (EDIT, Chord::ctrl(Key::Char('u')), "delete_to_start"),
    (EDIT, Chord::ctrl(Key::Char('k')), "delete_to_end"),
    (EDIT, Chord::ctrl(Key::Char('y')), "yank"),
    (EDIT, Chord::ctrl(Key::Char('t')), "transpose"),
    (COMPOSE, Chord::ctrl(Key::Char('p')), "history_prev"),
    (COMPOSE, Chord::ctrl(Key::Char('n')), "history_next"),
    (LIST, Chord::ctrl(Key::Char('p')), "modal_up"),
    (LIST, Chord::ctrl(Key::Char('n')), "modal_down"),
    (LIST, Chord::ctrl(Key::Char('g')), "modal_cancel"),
    // Shift+enter only arrives as its own chord on terminals that speak the
    // kitty keyboard protocol; alt+enter and ctrl+j cover the rest, and a
    // trailing backslash covers what neither does.
    (COMPOSE, Chord::shift(Key::Enter), "insert_newline"),
    (COMPOSE, Chord::alt(Key::Enter), "insert_newline"),
    (COMPOSE, Chord::ctrl(Key::Char('j')), "insert_newline"),
];

#[derive(Debug)]
pub struct Keymap {
    map: HashMap<(Mode, Chord), Binding>,
}

impl Default for Keymap {
    fn default() -> Self {
        let mut keymap = Self {
            map: HashMap::new(),
        };
        keymap.reset();
        keymap
    }
}

impl Keymap {
    pub fn set(&mut self, mode: Mode, chord: Chord, binding: Binding) {
        self.map.insert((mode, chord.normalised()), binding);
    }

    pub fn get(&self, mode: Mode, chord: Chord) -> Option<&Binding> {
        self.map.get(&(mode, chord.normalised()))
    }

    pub fn reset(&mut self) {
        self.map.clear();
        for (modes, chord, action) in DEFAULTS {
            for mode in modes.iter().copied() {
                self.set(mode, *chord, Binding::Action((*action).to_string()));
            }
        }
    }

    pub fn entries(&self) -> impl Iterator<Item = (&(Mode, Chord), &Binding)> {
        self.map.iter()
    }
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

#[cfg(test)]
mod tests {
    use super::{Binding, Chord, Key, Keymap, Mode, describe};

    fn action(keymap: &Keymap, mode: Mode, spec: &str) -> Option<String> {
        let chord = Chord::parse(spec)?;
        match keymap.get(mode, chord)? {
            Binding::Action(name) => Some(name.clone()),
            _ => None,
        }
    }

    #[test]
    fn readline_defaults_are_bound_where_there_is_text() {
        let keymap = Keymap::default();
        assert_eq!(
            action(&keymap, Mode::Normal, "<C-w>").as_deref(),
            Some("delete_word_back")
        );
        assert_eq!(
            action(&keymap, Mode::Prompt, "<C-a>").as_deref(),
            Some("cursor_start")
        );
        assert_eq!(
            action(&keymap, Mode::Select, "<C-u>").as_deref(),
            Some("delete_to_start")
        );
        assert!(action(&keymap, Mode::Confirm, "<C-w>").is_none());
    }

    /// Up and down mean the list in a modal and the history in the composer.
    #[test]
    fn previous_and_next_follow_the_mode() {
        let keymap = Keymap::default();
        assert_eq!(
            action(&keymap, Mode::Normal, "<C-p>").as_deref(),
            Some("history_prev")
        );
        assert_eq!(
            action(&keymap, Mode::Select, "<C-p>").as_deref(),
            Some("modal_up")
        );
        assert_eq!(
            action(&keymap, Mode::Suggest, "<C-n>").as_deref(),
            Some("modal_down")
        );
    }

    #[test]
    fn every_way_to_ask_for_a_newline_is_bound() {
        let keymap = Keymap::default();
        for spec in ["<S-CR>", "<A-CR>", "<C-j>"] {
            assert_eq!(
                action(&keymap, Mode::Normal, spec).as_deref(),
                Some("insert_newline"),
                "{spec} should insert a newline"
            );
        }
    }

    #[test]
    fn quit_is_bound_in_every_mode() {
        let keymap = Keymap::default();
        for mode in [
            Mode::Normal,
            Mode::Confirm,
            Mode::Select,
            Mode::Prompt,
            Mode::Suggest,
        ] {
            assert_eq!(action(&keymap, mode, "<C-c>").as_deref(), Some("quit"));
        }
    }

    #[test]
    fn a_binding_names_a_key_not_a_character() {
        let keymap = Keymap::default();
        let upper = Chord::new(Key::Char('W'), true, false, true);
        assert!(matches!(
            keymap.get(Mode::Normal, upper),
            Some(Binding::Action(name)) if name == "delete_word_back"
        ));
    }

    #[test]
    fn describing_a_chord_round_trips() {
        for spec in ["<C-w>", "<A-CR>", "<S-CR>", "<C-a>", "x"] {
            let chord = Chord::parse(spec);
            assert!(chord.is_some(), "{spec} should parse");
            let described = chord.map(describe).unwrap_or_default();
            assert_eq!(Chord::parse(&described), chord, "{spec} → {described}");
        }
    }
}
