use std::ffi::c_int;

use mlua::{FromLuaMulti, IntoLuaMulti, Lua, ffi};

#[derive(Clone, Copy)]
pub(crate) struct Stack(*mut ffi::lua_State);

#[allow(unsafe_code)]
pub(crate) fn build<R: FromLuaMulti>(
    lua: &Lua,
    args: impl IntoLuaMulti,
    fill: impl FnOnce(Stack),
) -> mlua::Result<R> {
    unsafe { lua.exec_raw(args, |state| fill(Stack(state))) }
}

#[allow(unsafe_code)]
impl Stack {
    pub(crate) fn top(self) -> c_int {
        unsafe { ffi::lua_gettop(self.0) }
    }

    pub(crate) fn reserve(self) -> bool {
        unsafe { ffi::lua_checkstack(self.0, ffi::LUA_MINSTACK) != 0 }
    }

    pub(crate) fn nil(self) {
        unsafe { ffi::lua_pushnil(self.0) };
    }

    pub(crate) fn null(self) {
        unsafe { ffi::lua_pushlightuserdata(self.0, std::ptr::null_mut()) };
    }

    pub(crate) fn boolean(self, value: bool) {
        unsafe { ffi::lua_pushboolean(self.0, c_int::from(value)) };
    }

    pub(crate) fn integer(self, value: i64) {
        unsafe { ffi::lua_pushinteger(self.0, value) };
    }

    pub(crate) fn number(self, value: f64) {
        unsafe { ffi::lua_pushnumber(self.0, value) };
    }

    pub(crate) fn string(self, value: &str) {
        unsafe { ffi::lua_pushlstring(self.0, value.as_ptr().cast(), value.len()) };
    }

    pub(crate) fn table(self, size: usize) {
        let size = c_int::try_from(size).unwrap_or_default();
        unsafe { ffi::lua_createtable(self.0, size, 0) };
    }

    pub(crate) fn set_index(self, index: i64) {
        unsafe { ffi::lua_rawseti(self.0, -2, index) };
    }

    pub(crate) fn set_field(self) {
        unsafe { ffi::lua_rawset(self.0, -3) };
    }

    pub(crate) fn set_metatable(self, metatable: c_int) {
        unsafe {
            ffi::lua_pushvalue(self.0, metatable);
            ffi::lua_setmetatable(self.0, -2);
        }
    }
}
