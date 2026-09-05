use std::rc::Rc;

use mlua::{Function, Lua as LuaState};

use crate::runtime::Inner;

pub(crate) fn current_provider(lua: &LuaState, inner: &Rc<Inner>) -> mlua::Result<Function> {
    let state = inner.state.clone();
    lua.create_function(move |_, ()| Ok(state.borrow().current_provider().map(str::to_string)))
}

pub(crate) fn current_model(lua: &LuaState, inner: &Rc<Inner>) -> mlua::Result<Function> {
    let state = inner.state.clone();
    lua.create_function(move |_, ()| Ok(state.borrow().current_model().map(str::to_string)))
}
