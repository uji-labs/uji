use std::collections::HashMap;
use std::str::FromStr;

use strum::{EnumString, IntoStaticStr, VariantArray};

use globset::GlobMatcher;
use regex::Regex;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, EnumString, IntoStaticStr, VariantArray)]
#[strum(serialize_all = "snake_case")]
pub enum Action {
    Allow,
    #[default]
    Ask,
    Deny,
}

impl Action {
    pub fn parse(value: &str) -> Option<Self> {
        Self::from_str(value).ok()
    }

    fn strictness(self) -> u8 {
        match self {
            Self::Allow => 0,
            Self::Ask => 1,
            Self::Deny => 2,
        }
    }

    #[must_use]
    pub fn strictest(self, other: Self) -> Self {
        if other.strictness() > self.strictness() {
            other
        } else {
            self
        }
    }
}

#[derive(Debug, Clone)]
pub enum Matcher {
    Exact(String),
    Glob(GlobMatcher),
    Regex(Regex),
}

impl Matcher {
    pub fn matches(&self, subject: &str) -> bool {
        match self {
            Matcher::Exact(pattern) => pattern == subject,
            Matcher::Glob(glob) => glob.is_match(subject),
            Matcher::Regex(regex) => regex.is_match(subject),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Rule {
    pub matcher: Matcher,
    pub action: Action,
}

#[derive(Debug, Clone, Default)]
pub struct ToolRules {
    pub rules: Vec<Rule>,
    pub default: Action,
}

#[derive(Debug, Clone)]
pub struct ToolPolicy {
    pub tools: HashMap<String, ToolRules>,
    pub default: Action,
}

impl Default for ToolPolicy {
    fn default() -> Self {
        let mut tools = HashMap::new();
        for name in ["read_file", "list_dir", "grep"] {
            tools.insert(
                name.to_string(),
                ToolRules {
                    rules: Vec::new(),
                    default: Action::Allow,
                },
            );
        }
        for name in ["edit_file", "write_file", "run_command"] {
            tools.insert(
                name.to_string(),
                ToolRules {
                    rules: Vec::new(),
                    default: Action::Ask,
                },
            );
        }
        Self {
            tools,
            default: Action::Ask,
        }
    }
}

impl ToolPolicy {
    pub fn names(&self) -> impl Iterator<Item = &str> {
        self.tools.keys().map(String::as_str)
    }

    pub fn evaluate(&self, tool: &str, subject: &str) -> Action {
        let Some(rules) = self.tools.get(tool) else {
            return self.default;
        };
        rules
            .rules
            .iter()
            .find(|rule| rule.matcher.matches(subject))
            .map_or(rules.default, |rule| rule.action)
    }
}
