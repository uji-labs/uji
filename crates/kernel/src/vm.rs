use std::path::PathBuf;

use mlua::{Function, Lua, MultiValue, Table, Value};

use crate::{
    clipboard, codec, db, executor, fs, fuzzy, keychain, matcher, net, os, proc, promise, tty,
};

const AFTER_PRELOAD: i64 = 2;

pub enum Sources {
    Embedded(&'static [(&'static str, &'static str)]),
    Directory(PathBuf),
}

impl Sources {
    fn find(&self, module: &str) -> Option<(String, Vec<u8>)> {
        let relative = module.replace('.', "/");
        [format!("{relative}.lua"), format!("{relative}/init.lua")]
            .into_iter()
            .find_map(|file| self.read(&file).map(|source| (self.name(&file), source)))
    }

    fn read(&self, file: &str) -> Option<Vec<u8>> {
        match self {
            Self::Embedded(files) => files
                .iter()
                .find(|(name, _)| *name == file)
                .map(|(_, source)| source.as_bytes().to_vec()),
            Self::Directory(root) => std::fs::read(root.join(file)).ok(),
        }
    }

    fn name(&self, file: &str) -> String {
        match self {
            Self::Embedded(_) => file.to_string(),
            Self::Directory(root) => root.join(file).display().to_string(),
        }
    }
}

pub(crate) fn create(sources: Sources) -> mlua::Result<Lua> {
    let lua = Lua::new();
    install_searcher(&lua, sources)?;
    let uji = lua.create_table()?;
    uji.set("task", executor::register(&lua)?)?;
    uji.set("sleep", executor::sleep(&lua)?)?;
    uji.set("promise", promise::constructor(&lua)?)?;
    uji.set("fs", fs::register(&lua)?)?;
    uji.set("proc", proc::register(&lua)?)?;
    uji.set("net", net::register(&lua)?)?;
    uji.set("tty", tty::register(&lua)?)?;
    uji.set("db", db::register(&lua)?)?;
    uji.set("keychain", keychain::register(&lua)?)?;
    uji.set("os", os::register(&lua)?)?;
    uji.set("clipboard", clipboard::register(&lua)?)?;
    uji.set("regex", matcher::regex(&lua)?)?;
    uji.set("glob", matcher::glob(&lua)?)?;
    uji.set("fuzzy", fuzzy::function(&lua)?)?;
    codec::install(&lua, &uji)?;
    lua.globals().set("uji", uji)?;
    Ok(lua)
}

pub(crate) fn entry(lua: &Lua, module: &str) -> mlua::Result<Function> {
    lua.globals().get::<Function>("require")?.call(module)
}

fn install_searcher(lua: &Lua, sources: Sources) -> mlua::Result<()> {
    let searcher = lua.create_function(move |lua, module: String| {
        let Some((name, source)) = sources.find(&module) else {
            return Ok(MultiValue::from_vec(vec![Value::String(
                lua.create_string(format!("\n\tno runtime module '{module}'"))?,
            )]));
        };
        let chunk = lua
            .load(source)
            .set_name(format!("@{name}"))
            .into_function()?;
        Ok(MultiValue::from_vec(vec![
            Value::Function(chunk),
            Value::String(lua.create_string(&name)?),
        ]))
    })?;
    let package: Table = lua.globals().get("package")?;
    let searchers: Table = package.get("searchers")?;
    searchers.raw_insert(AFTER_PRELOAD, searcher)
}
