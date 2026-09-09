use std::rc::Rc;

use crate::model::{UiConfig, WinOpts, WindowKind};
use crate::state::UiState;
use mlua::{Function, Lua, LuaSerdeExt, Table, Value as LuaValue};

use super::Api;
use super::convert::FromLuaValue;

pub fn open(state: &mut UiState, kind: WindowKind, lines: Vec<String>, opts: WinOpts) -> u32 {
    state.push_window(kind, lines, opts)
}

pub fn close(state: &mut UiState, id: u32) -> bool {
    state.close_window(id)
}

pub fn open_win(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, opts: Option<Table>| {
        let (kind, lines, win_opts) = match opts {
            Some(table) => {
                let kind = match table.get::<Option<String>>("view")? {
                    Some(view) => view
                        .parse::<WindowKind>()
                        .map_err(|err| mlua::Error::runtime(err.to_string()))?,
                    None => WindowKind::Text,
                };
                let lines = table
                    .get::<Option<Vec<String>>>("lines")?
                    .unwrap_or_default();
                let win_opts = WinOpts::from_lua_value(&LuaValue::Table(table))?;
                (kind, lines, win_opts)
            }
            None => (WindowKind::Text, Vec::new(), WinOpts::default()),
        };
        let mut state = state.borrow_mut();
        Ok(open(&mut state, kind, lines, win_opts))
    })
}

pub fn close_win(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, id: u32| {
        let mut state = state.borrow_mut();
        Ok(close(&mut state, id))
    })
}

pub fn configure(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |lua, opts: Table| {
        let config: UiConfig = lua.from_value(LuaValue::Table(opts))?;
        state.borrow_mut().apply_config(&config);
        Ok(())
    })
}
