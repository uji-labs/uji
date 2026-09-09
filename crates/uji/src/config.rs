use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;

use mlua::Lua;
use uji_api::Api;
use uji_api::model::UiModel;
use uji_api::state::UiState;

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

fn from_lua(source: &str, name: &str) -> Result<UiModel, mlua::Error> {
    let lua = Lua::new();
    let api = Api::new(Rc::new(RefCell::new(UiState::new())));
    let uji = uji_api::register(&lua, &api)?;
    lua.globals().set("uji", uji)?;
    lua.load(source).set_name(name).exec()?;
    let inner = Inner::new(lua, api);
    Ok(inner.state().borrow().snapshot())
}
