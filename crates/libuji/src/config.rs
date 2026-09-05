use std::path::PathBuf;

use mlua::{Lua, Table};
use tui::model::{GlobalOpts, UiModel};

use crate::runtime::Inner;

pub const DEFAULT_LUA: &str = include_str!("../config/default.lua");

pub fn load() -> UiModel {
    let Some(path) = config_path() else {
        return embedded_default();
    };
    match std::fs::read_to_string(&path) {
        Ok(source) => match from_lua(&source, &path.display().to_string()) {
            Ok(model) => model,
            Err(err) => {
                eprintln!("uji: config error in {}: {err}", path.display());
                embedded_default()
            }
        },
        Err(err) => {
            eprintln!("uji: cannot read config {}: {err}", path.display());
            embedded_default()
        }
    }
}

fn embedded_default() -> UiModel {
    from_lua(DEFAULT_LUA, "default.lua").unwrap_or_default()
}

pub(crate) fn config_path() -> Option<PathBuf> {
    if let Some(path) = std::env::var("UJI_CONFIG").ok().filter(|p| !p.is_empty()) {
        return Some(PathBuf::from(path));
    }
    let home = std::env::var("HOME").ok()?;
    let path = PathBuf::from(home).join(".config/uji/init.lua");
    path.is_file().then_some(path)
}

pub(crate) fn plugin_dir() -> Option<PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let path = PathBuf::from(home).join(".config/uji/lua/plugins");
    path.is_dir().then_some(path)
}

pub(crate) fn watch_paths() -> Vec<PathBuf> {
    if let Some(path) = std::env::var("UJI_CONFIG").ok().filter(|p| !p.is_empty()) {
        let path = PathBuf::from(path);
        return if path.is_file() {
            vec![path]
        } else {
            Vec::new()
        };
    }
    if let Ok(home) = std::env::var("HOME") {
        let dir = PathBuf::from(home).join(".config/uji");
        if dir.is_dir() {
            return vec![dir];
        }
    }
    Vec::new()
}

fn from_lua(source: &str, name: &str) -> Result<UiModel, mlua::Error> {
    let inner = Inner::new(Lua::new());
    let uji = crate::lua::functions::register_all(&inner.lua, &inner)?;
    inner.lua.globals().set("uji", uji)?;
    inner.lua.load(source).set_name(name).exec()?;

    let cursor_blink = inner
        .lua
        .globals()
        .get::<Table>("uji")
        .and_then(|uji| uji.get::<Table>("ui"))
        .and_then(|ui| ui.get::<Table>("opt"))
        .ok()
        .and_then(|opt| opt.get::<Option<bool>>("cursor_blink").ok().flatten())
        .unwrap_or(true);

    let state = inner.state.borrow();
    Ok(UiModel {
        buffers: state.buffers().to_vec(),
        windows: state.windows().to_vec(),
        opts: GlobalOpts {
            cursor_blink,
            ..GlobalOpts::default()
        },
    })
}
