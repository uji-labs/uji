use globset::Glob;
use mlua::{Lua, Table, Value as LuaValue};
use regex::Regex;

use super::policy::{Action, Matcher, Rule, ToolPolicy, ToolRules};

pub fn compile(lua: &Lua) -> ToolPolicy {
    let mut policy = ToolPolicy::default();
    let Some(table) = policy_table(lua) else {
        return policy;
    };
    if let Ok(Some(default)) = table.get::<Option<String>>("default")
        && let Some(action) = Action::parse(&default)
    {
        policy.default = action;
    }
    for pair in table.pairs::<String, LuaValue>() {
        let Ok((name, value)) = pair else {
            continue;
        };
        if name == "default" {
            continue;
        }
        if let Some(rules) = tool_rules(value) {
            policy.tools.insert(name, rules);
        }
    }
    policy
}

fn policy_table(lua: &Lua) -> Option<Table> {
    let uji: Table = lua.globals().get("uji").ok()?;
    let tool: Table = uji.get("tool").ok()?;
    tool.get("policy").ok()
}

fn tool_rules(value: LuaValue) -> Option<ToolRules> {
    let LuaValue::Table(table) = value else {
        return None;
    };
    let mut rules = Vec::new();
    let mut default = Action::Ask;
    if let Ok(Some(value)) = table.get::<Option<String>>("default")
        && let Some(action) = Action::parse(&value)
    {
        default = action;
    }
    for key in ["deny", "allow", "ask"] {
        let action = Action::parse(key)?;
        if let Ok(Some(entries)) = table.get::<Option<Vec<String>>>(key) {
            for entry in entries {
                match matcher(&entry) {
                    Some(matcher) => rules.push(Rule { matcher, action }),
                    None => eprintln!("uji: bad policy rule: {entry}"),
                }
            }
        }
    }
    Some(ToolRules { rules, default })
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
