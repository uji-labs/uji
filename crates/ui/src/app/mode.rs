use super::line::Line;
use crate::model::Builtin;
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SuggestItem {
    pub name: String,
    pub desc: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Echo {
    Plain,
    Hidden,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mode {
    Normal,
    Select {
        title: String,
        items: Vec<String>,
        query: Line,
        cursor: usize,
        matches: Vec<usize>,
    },
    /// A picker: fuzzy-filtered results beside a preview of the highlighted one.
    Pick {
        title: String,
        items: Vec<String>,
        query: Line,
        cursor: usize,
        matches: Vec<usize>,
        /// Lines for the highlighted item, and which match they belong to.
        preview: Vec<String>,
        previewed: Option<usize>,
        /// Set when the picker asks Lua for a fresh item list per keystroke.
        live: bool,
    },
    Prompt {
        title: String,
        value: Line,
        echo: Echo,
    },
    Suggest {
        items: Vec<SuggestItem>,
        cursor: usize,
    },
    Confirm {
        title: String,
        body: String,
        allow: bool,
    },
}

impl Mode {
    /// The window this mode puts in focus — uji's equivalent of neovim's
    /// `curwin`. Whatever is focused receives keys and draws the cursor, so the
    /// two cannot disagree.
    pub fn focus(&self) -> Builtin {
        match self {
            Self::Normal => Builtin::Input,
            Self::Select { .. }
            | Self::Pick { .. }
            | Self::Prompt { .. }
            | Self::Suggest { .. }
            | Self::Confirm { .. } => Builtin::Modal,
        }
    }
}
