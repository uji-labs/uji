use std::fmt;
use std::str::FromStr;

use serde::Deserialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Builtin {
    Messages,
    Input,
}

impl fmt::Display for Builtin {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Messages => "messages",
            Self::Input => "input",
        })
    }
}

impl FromStr for Builtin {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "messages" => Ok(Self::Messages),
            "input" => Ok(Self::Input),
            other => Err(ParseError(format!(
                "unknown view: {other} (expected \"messages\" or \"input\")"
            ))),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Color {
    Black,
    Red,
    Green,
    Yellow,
    Blue,
    Magenta,
    Cyan,
    Gray,
    DarkGray,
    LightRed,
    LightGreen,
    LightYellow,
    LightBlue,
    LightMagenta,
    LightCyan,
    White,
    Rgb(u8, u8, u8),
}

impl FromStr for Color {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        if let Some(hex) = s.strip_prefix('#') {
            if hex.len() != 6 {
                return Err(ParseError(format!("invalid color: {s} (expected #rrggbb)")));
            }
            let parse = |i: usize| {
                u8::from_str_radix(&hex[i..i + 2], 16)
                    .map_err(|_| ParseError(format!("invalid color: {s}")))
            };
            return Ok(Self::Rgb(parse(0)?, parse(2)?, parse(4)?));
        }
        match s {
            "black" => Ok(Self::Black),
            "red" => Ok(Self::Red),
            "green" => Ok(Self::Green),
            "yellow" => Ok(Self::Yellow),
            "blue" => Ok(Self::Blue),
            "magenta" => Ok(Self::Magenta),
            "cyan" => Ok(Self::Cyan),
            "white" => Ok(Self::White),
            "gray" | "grey" => Ok(Self::Gray),
            "dark_gray" | "dark_grey" | "light_black" => Ok(Self::DarkGray),
            "light_red" => Ok(Self::LightRed),
            "light_green" => Ok(Self::LightGreen),
            "light_yellow" => Ok(Self::LightYellow),
            "light_blue" => Ok(Self::LightBlue),
            "light_magenta" => Ok(Self::LightMagenta),
            "light_cyan" => Ok(Self::LightCyan),
            other => Err(ParseError(format!("unknown color: {other}"))),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Style {
    pub fg: Option<Color>,
    pub bg: Option<Color>,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Span {
    pub text: String,
    pub style: Style,
}

impl Span {
    pub fn new(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            style: Style::default(),
        }
    }

    pub fn styled(text: impl Into<String>, style: Style) -> Self {
        Self {
            text: text.into(),
            style,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Line {
    pub spans: Vec<Span>,
}

impl Line {
    pub fn blank() -> Self {
        Self { spans: Vec::new() }
    }

    pub fn single(span: Span) -> Self {
        Self { spans: vec![span] }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Border {
    #[default]
    None,
    Plain,
    Rounded,
    Horizontal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Size {
    Fill,
    Fixed(u16),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Split {
    #[default]
    Top,
    Bottom,
    Left,
    Right,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WinOpts {
    pub split: Split,
    pub size: Size,
    pub border: Border,
    pub title: Option<String>,
    pub wrap: bool,
    pub border_color: Option<Color>,
}

impl Default for WinOpts {
    fn default() -> Self {
        Self {
            split: Split::Top,
            size: Size::Fill,
            border: Border::None,
            title: None,
            wrap: false,
            border_color: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct WindowSpec {
    pub id: u32,
    pub builtin: Option<Builtin>,
    pub buffer: Vec<Line>,
    pub opts: WinOpts,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GlobalOpts {
    pub cursor_blink: bool,
    pub input_color: Option<Color>,
    pub suggest_enabled: bool,
    pub suggest_max_height: u16,
    pub loader_frames: Vec<String>,
    pub loader_interval_ms: u64,
    pub agent_system_prompt: Option<String>,
}

impl Default for GlobalOpts {
    fn default() -> Self {
        Self {
            cursor_blink: true,
            input_color: None,
            suggest_enabled: true,
            suggest_max_height: 5,
            loader_frames: Vec::new(),
            loader_interval_ms: 80,
            agent_system_prompt: None,
        }
    }
}

#[derive(Debug, Clone, Deserialize, Default)]
#[serde(default)]
pub struct UiConfig {
    pub input: InputConfig,
    pub suggest: SuggestConfig,
    pub waiting: WaitingConfig,
    pub agent: AgentConfig,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct AgentConfig {
    pub system_prompt: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct InputConfig {
    pub cursor_blink: Option<bool>,
    pub text_color: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct SuggestConfig {
    pub enabled: Option<bool>,
    pub max_height: Option<u16>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct LoaderConfig {
    pub frames: Option<Vec<String>>,
    pub interval_ms: Option<u64>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct WaitingConfig {
    pub loader: Option<LoaderConfig>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RunState {
    #[default]
    Idle,
    Working,
    Error,
}

#[derive(Debug, Clone, PartialEq)]
pub struct UiModel {
    pub windows: Vec<WindowSpec>,
    pub opts: GlobalOpts,
}

impl Default for UiModel {
    fn default() -> Self {
        Self {
            windows: vec![
                WindowSpec {
                    id: 0,
                    builtin: Some(Builtin::Messages),
                    buffer: Vec::new(),
                    opts: WinOpts {
                        split: Split::Top,
                        size: Size::Fill,
                        wrap: true,
                        ..WinOpts::default()
                    },
                },
                WindowSpec {
                    id: 1,
                    builtin: None,
                    buffer: Vec::new(),
                    opts: WinOpts {
                        split: Split::Bottom,
                        size: Size::Fixed(1),
                        ..WinOpts::default()
                    },
                },
                WindowSpec {
                    id: 2,
                    builtin: Some(Builtin::Input),
                    buffer: Vec::new(),
                    opts: WinOpts {
                        split: Split::Bottom,
                        size: Size::Fixed(3),
                        border: Border::Horizontal,
                        ..WinOpts::default()
                    },
                },
            ],
            opts: GlobalOpts::default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError(pub String);

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ParseError {}

impl FromStr for Split {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "top" => Ok(Self::Top),
            "bottom" => Ok(Self::Bottom),
            "left" => Ok(Self::Left),
            "right" => Ok(Self::Right),
            other => Err(ParseError(format!("unknown split: {other}"))),
        }
    }
}

impl fmt::Display for Split {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Top => "top",
            Self::Bottom => "bottom",
            Self::Left => "left",
            Self::Right => "right",
        })
    }
}

impl FromStr for Border {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "none" => Ok(Self::None),
            "plain" => Ok(Self::Plain),
            "rounded" => Ok(Self::Rounded),
            "horizontal" => Ok(Self::Horizontal),
            other => Err(ParseError(format!("unknown border: {other}"))),
        }
    }
}

impl fmt::Display for Border {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::None => "none",
            Self::Plain => "plain",
            Self::Rounded => "rounded",
            Self::Horizontal => "horizontal",
        })
    }
}

impl From<u16> for Size {
    fn from(n: u16) -> Self {
        Self::Fixed(n)
    }
}

impl FromStr for Size {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "fill" => Ok(Self::Fill),
            other => Err(ParseError(format!(
                "unknown size: {other} (expected \"fill\")"
            ))),
        }
    }
}

impl fmt::Display for Size {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Fill => f.write_str("fill"),
            Self::Fixed(n) => write!(f, "{n}"),
        }
    }
}
