use std::rc::Rc;

use mlua::{Function, Lua as LuaState};

use crate::runtime::Inner;

pub(crate) fn command(lua: &LuaState, inner: &Rc<Inner>) -> mlua::Result<Function> {
    let inner = inner.clone();
    lua.create_function(move |_, (name, handler): (String, Function)| {
        inner.commands.borrow_mut().insert(name, handler);
        Ok(())
    })
}
