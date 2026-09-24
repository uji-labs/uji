use std::str::FromStr;

use serde::Deserialize;
use strum::{Display, EnumString, IntoStaticStr, VariantArray};

#[derive(
    Debug, Clone, Copy, Default, PartialEq, Eq, Display, EnumString, IntoStaticStr, VariantArray,
)]
#[strum(serialize_all = "snake_case", ascii_case_insensitive)]
pub enum Effort {
    #[default]
    Off,
    Minimal,
    Low,
    Medium,
    High,
}

pub const DEFAULT_MAX_OUTPUT: u32 = 8192;

impl Effort {
    pub fn enabled(self) -> bool {
        self != Self::Off
    }

    pub fn parse(name: &str) -> Option<Self> {
        Self::from_str(name).ok()
    }

    pub fn name(self) -> &'static str {
        self.into()
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, IntoStaticStr, Deserialize)]
#[strum(serialize_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum Retention {
    Off,
    #[default]
    Short,
    Long,
}

impl Retention {
    pub fn name(self) -> &'static str {
        self.into()
    }
}
