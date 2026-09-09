use std::fmt;
use std::str::FromStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WindowKind {
    Messages,
    Input,
    Status,
    Text,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Border {
    #[default]
    None,
    Plain,
    Rounded,
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
}

impl Default for WinOpts {
    fn default() -> Self {
        Self {
            split: Split::Top,
            size: Size::Fill,
            border: Border::None,
            title: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct WindowSpec {
    pub id: u32,
    pub kind: WindowKind,
    pub lines: Vec<String>,
    pub opts: WinOpts,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GlobalOpts {
    pub cursor_blink: bool,
    pub suggest_enabled: bool,
    pub suggest_max_height: u16,
    pub footer_hint: String,
    pub waiting: WaitingOpts,
}

impl Default for GlobalOpts {
    fn default() -> Self {
        Self {
            cursor_blink: true,
            suggest_enabled: true,
            suggest_max_height: 5,
            footer_hint: "ctrl+c exit".into(),
            waiting: WaitingOpts::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum RunState {
    #[default]
    Idle,
    Working,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WaitingOpts {
    pub text: String,
    pub loader_frames: Vec<String>,
    pub loader_interval_ms: u64,
}

impl Default for WaitingOpts {
    fn default() -> Self {
        Self {
            text: "Working".into(),
            loader_frames: Vec::new(),
            loader_interval_ms: 80,
        }
    }
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
                    kind: WindowKind::Messages,
                    lines: Vec::new(),
                    opts: WinOpts {
                        split: Split::Top,
                        size: Size::Fill,
                        ..WinOpts::default()
                    },
                },
                WindowSpec {
                    id: 1,
                    kind: WindowKind::Status,
                    lines: Vec::new(),
                    opts: WinOpts {
                        split: Split::Bottom,
                        size: Size::Fixed(1),
                        border: Border::None,
                        ..WinOpts::default()
                    },
                },
                WindowSpec {
                    id: 2,
                    kind: WindowKind::Input,
                    lines: Vec::new(),
                    opts: WinOpts {
                        split: Split::Bottom,
                        size: Size::Fixed(3),
                        border: Border::None,
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

impl FromStr for WindowKind {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "messages" => Ok(Self::Messages),
            "input" => Ok(Self::Input),
            "status" => Ok(Self::Status),
            "text" => Ok(Self::Text),
            other => Err(ParseError(format!(
                "unknown window kind: {other} (expected \"messages\", \"input\", \"status\" or \"text\")"
            ))),
        }
    }
}

impl fmt::Display for WindowKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Messages => "messages",
            Self::Input => "input",
            Self::Status => "status",
            Self::Text => "text",
        })
    }
}

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
