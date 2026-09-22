use std::collections::BTreeSet;

use globset::Glob;
use mlua::{Lua, Table, Value as LuaValue};
use regex::Regex;

use strum::VariantArray;
use uji_agent::tools::policy::{Action, Matcher, Rule, ToolPolicy, ToolRules};

const PRECEDENCE: [Action; Action::VARIANTS.len()] = [Action::Deny, Action::Allow, Action::Ask];

pub(super) fn compile(lua: &Lua, known: &BTreeSet<String>) -> (ToolPolicy, Vec<String>) {
    let mut policy = ToolPolicy::default();
    let mut notices = Vec::new();
    let Some(table) = policy_table(lua) else {
        return (policy, notices);
    };
    if let Ok(Some(default)) = table.get::<Option<String>>("default") {
        match Action::parse(&default) {
            Some(action) => policy.default = action,
            None => notices.push(format!(
                "tool policy: default `{default}` is not allow, ask or deny; asking instead"
            )),
        }
    }
    for pair in table.pairs::<String, LuaValue>() {
        let Ok((name, value)) = pair else {
            continue;
        };
        if name == "default" {
            continue;
        }
        if !known.contains(&name) {
            notices.push(format!(
                "tool policy: `{name}` is not a tool, so its rules do nothing"
            ));
            continue;
        }
        policy
            .tools
            .insert(name.clone(), tool_rules(&name, value, &mut notices));
    }
    (policy, notices)
}

fn policy_table(lua: &Lua) -> Option<Table> {
    let uji: Table = lua.globals().get("uji").ok()?;
    let tool: Table = uji.get("tool").ok()?;
    tool.get("policy").ok()
}

fn tool_rules(name: &str, value: LuaValue, notices: &mut Vec<String>) -> ToolRules {
    let LuaValue::Table(table) = value else {
        notices.push(format!(
            "tool policy: `{name}` is not a table of rules; asking before every {name}"
        ));
        return ToolRules {
            rules: Vec::new(),
            default: Action::Ask,
        };
    };
    let mut rules = Vec::new();
    let mut default = Action::Ask;
    if let Ok(Some(value)) = table.get::<Option<String>>("default") {
        match Action::parse(&value) {
            Some(action) => default = action,
            None => notices.push(format!(
                "tool policy: `{name}` default `{value}` is not allow, ask or deny; asking instead"
            )),
        }
    }
    let mut unreadable = false;
    for action in PRECEDENCE {
        let key: &'static str = action.into();
        if let Ok(Some(entries)) = table.get::<Option<Vec<String>>>(key) {
            let (readable, broken): (Vec<_>, Vec<_>) = entries
                .into_iter()
                .map(|entry| {
                    matcher(&entry)
                        .map(|matcher| Rule { matcher, action })
                        .ok_or(entry)
                })
                .partition(Result::is_ok);
            rules.extend(readable.into_iter().filter_map(Result::ok));
            unreadable |= !broken.is_empty();
            notices.extend(broken.into_iter().filter_map(Result::err).map(|entry| {
                format!("tool policy: `{name}` {key} rule `{entry}` is not a valid pattern")
            }));
        }
    }
    if unreadable {
        let raised = default.strictest(Action::Ask);
        if raised != default {
            notices.push(format!(
                "tool policy: asking before every {name}, because part of its policy could not be read"
            ));
            default = raised;
        }
    }
    ToolRules { rules, default }
}

fn matcher(value: &str) -> Option<Matcher> {
    let bytes = value.as_bytes();
    if bytes.len() >= 2 && bytes[0] == b'/' && bytes[bytes.len() - 1] == b'/' {
        let pattern = &value[1..value.len() - 1];
        return Regex::new(pattern).ok().map(Matcher::Regex);
    }
    if value.contains(['*', '?', '[']) {
        return Glob::new(value)
            .ok()
            .map(|glob| Matcher::Glob(glob.compile_matcher()));
    }
    Some(Matcher::Exact(value.to_string()))
}
