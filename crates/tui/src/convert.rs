use std::fmt;
use std::str::FromStr;

use crate::model::{Border, BufferKind, Size, Split};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError(pub String);

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ParseError {}

impl FromStr for BufferKind {
    type Err = ParseError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "messages" => Ok(Self::Messages),
            "input" => Ok(Self::Input),
            "status" => Ok(Self::Status),
            other => Err(ParseError(format!(
                "unknown buffer kind: {other} (expected \"messages\", \"input\" or \"status\")"
            ))),
        }
    }
}

impl fmt::Display for BufferKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Messages => "messages",
            Self::Input => "input",
            Self::Status => "status",
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
