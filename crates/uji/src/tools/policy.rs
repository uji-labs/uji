use std::collections::HashMap;

use globset::GlobMatcher;
use regex::Regex;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Action {
    Allow,
    #[default]
    Ask,
    Deny,
}

impl Action {
    pub fn parse(value: &str) -> Option<Action> {
        match value {
            "allow" => Some(Action::Allow),
            "ask" => Some(Action::Ask),
            "deny" => Some(Action::Deny),
            _ => None,
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
        for name in ["write_file", "run_command"] {
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
    pub fn evaluate(&self, tool: &str, subject: &str) -> Action {
        let Some(rules) = self.tools.get(tool) else {
            return self.default;
        };
        for rule in &rules.rules {
            if rule.matcher.matches(subject) {
                return rule.action;
            }
        }
        rules.default
    }
}
