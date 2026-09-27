use std::time::{SystemTime, UNIX_EPOCH};

use mlua::{Lua, Table};

use crate::kernel::State;

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|elapsed| i64::try_from(elapsed.as_millis()).ok())
        .unwrap_or_default()
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let os = lua.create_table()?;
    os.set("platform", platform())?;
    os.set(
        "env",
        lua.create_function(|_, name: String| {
            Ok(std::env::var(name).ok().filter(|value| !value.is_empty()))
        })?,
    )?;
    os.set(
        "cwd",
        lua.create_function(|_, ()| {
            std::env::current_dir()
                .map(|dir| dir.display().to_string())
                .map_err(mlua::Error::external)
        })?,
    )?;
    os.set(
        "home",
        lua.create_function(|_, ()| Ok(std::env::home_dir().map(|dir| dir.display().to_string())))?,
    )?;
    os.set("now", lua.create_function(|_, ()| Ok(now()))?)?;
    os.set(
        "clock",
        lua.create_function(|lua, ()| Ok(State::of(lua)?.started.elapsed().as_secs_f64()))?,
    )?;
    os.set(
        "exit",
        lua.create_function(|lua, code: Option<u8>| {
            State::of_mut(lua)?.exit = Some(code.unwrap_or(0));
            Ok(())
        })?,
    )?;
    Ok(os)
}

fn platform() -> &'static str {
    match std::env::consts::OS {
        "macos" => "macos",
        "linux" => "linux",
        "windows" => "windows",
        _ => "other",
    }
}
