use mlua::{Function, Lua};
use nucleo_matcher::pattern::{CaseMatching, Normalization, Pattern};
use nucleo_matcher::{Config, Matcher};

struct Candidate<'a> {
    at: usize,
    text: &'a str,
}

impl AsRef<str> for Candidate<'_> {
    fn as_ref(&self) -> &str {
        self.text
    }
}

fn rank(items: &[String], query: &str) -> Vec<usize> {
    if query.is_empty() {
        return (1..=items.len()).collect();
    }
    let mut matcher = Matcher::new(Config::DEFAULT.match_paths());
    let candidates = items.iter().enumerate().map(|(at, text)| Candidate {
        at: at.saturating_add(1),
        text: text.as_str(),
    });
    Pattern::parse(query, CaseMatching::Ignore, Normalization::Smart)
        .match_list(candidates, &mut matcher)
        .into_iter()
        .map(|(candidate, _)| candidate.at)
        .collect()
}

pub(crate) fn function(lua: &Lua) -> mlua::Result<Function> {
    lua.create_function(|_, (query, items): (String, Vec<String>)| Ok(rank(&items, &query)))
}
