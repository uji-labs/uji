use globset::{GlobBuilder, GlobMatcher};
use mlua::{Function, IntoLuaMulti, Lua, MultiValue, Table, UserData, UserDataMethods};
use regex::Regex;

use crate::io;

pub(crate) enum Matcher {
    Regex(Regex),
    Glob(GlobMatcher),
}

impl Matcher {
    fn find(&self, subject: &str) -> Option<(usize, usize)> {
        match self {
            Self::Regex(regex) => regex
                .find(subject)
                .map(|found| (found.start(), found.end())),
            Self::Glob(glob) => glob.is_match(subject).then_some((0, subject.len())),
        }
    }
}

impl UserData for Matcher {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("test", |_, matcher, subject: mlua::LuaString| {
            Ok(matcher.find(&subject.to_string_lossy()).is_some())
        });
        methods.add_method(
            "find",
            |lua, matcher, subject: mlua::LuaString| match matcher.find(&subject.to_string_lossy())
            {
                Some((start, end)) => (start.saturating_add(1), end).into_lua_multi(lua),
                None => Ok(MultiValue::new()),
            },
        );
    }
}

pub(crate) fn regex(lua: &Lua) -> mlua::Result<Function> {
    lua.create_function(|lua, pattern: String| {
        io::settle(lua, Regex::new(&pattern).map(Matcher::Regex))
    })
}

pub(crate) fn glob(lua: &Lua) -> mlua::Result<Function> {
    lua.create_function(|lua, (pattern, opts): (String, Option<Table>)| {
        let separator = opts
            .map(|opts| opts.get::<Option<bool>>("separator"))
            .transpose()?
            .flatten()
            .unwrap_or(false);
        let built = GlobBuilder::new(&pattern)
            .literal_separator(separator)
            .build()
            .map(|glob| Matcher::Glob(glob.compile_matcher()));
        io::settle(lua, built)
    })
}
