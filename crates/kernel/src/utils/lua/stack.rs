use std::ffi::c_int;

use mlua::{FromLua, IntoLuaMulti, Lua, Value, ffi};

pub(crate) struct Stack {
    state: *mut ffi::lua_State,
    built: bool,
}

#[allow(unsafe_code)]
pub(crate) fn build<R: FromLua>(
    lua: &Lua,
    args: impl IntoLuaMulti,
    fill: impl FnOnce(&Stack) -> mlua::Result<()>,
) -> mlua::Result<R> {
    let mut filled = Ok(());
    let value = unsafe {
        lua.exec_raw::<Value>(args, |state| {
            let mut stack = Stack {
                state,
                built: false,
            };
            filled = fill(&stack);
            stack.built = filled.is_ok();
        })?
    };
    filled?;
    R::from_lua(value, lua)
}

#[allow(unsafe_code)]
impl Drop for Stack {
    fn drop(&mut self) {
        unsafe {
            if self.built && ffi::lua_gettop(self.state) > 0 {
                ffi::lua_insert(self.state, 1);
                ffi::lua_settop(self.state, 1);
            } else {
                ffi::lua_settop(self.state, 0);
            }
        }
    }
}

#[allow(unsafe_code)]
impl Stack {
    pub(crate) fn top(&self) -> c_int {
        unsafe { ffi::lua_gettop(self.state) }
    }

    pub(crate) fn reserve(&self) -> bool {
        unsafe { ffi::lua_checkstack(self.state, ffi::LUA_MINSTACK) != 0 }
    }

    pub(crate) fn nil(&self) {
        unsafe { ffi::lua_pushnil(self.state) };
    }

    pub(crate) fn null(&self) {
        unsafe { ffi::lua_pushlightuserdata(self.state, std::ptr::null_mut()) };
    }

    pub(crate) fn boolean(&self, value: bool) {
        unsafe { ffi::lua_pushboolean(self.state, c_int::from(value)) };
    }

    pub(crate) fn integer(&self, value: i64) {
        unsafe { ffi::lua_pushinteger(self.state, value) };
    }

    pub(crate) fn number(&self, value: f64) {
        unsafe { ffi::lua_pushnumber(self.state, value) };
    }

    pub(crate) fn string(&self, value: &str) {
        unsafe { ffi::lua_pushlstring(self.state, value.as_ptr().cast(), value.len()) };
    }

    pub(crate) fn table(&self, size: usize) {
        let size = c_int::try_from(size).unwrap_or_default();
        unsafe { ffi::lua_createtable(self.state, size, 0) };
    }

    pub(crate) fn set_index(&self, index: i64) {
        unsafe { ffi::lua_rawseti(self.state, -2, index) };
    }

    pub(crate) fn set_field(&self) {
        unsafe { ffi::lua_rawset(self.state, -3) };
    }

    pub(crate) fn set_metatable(&self, metatable: c_int) {
        unsafe {
            ffi::lua_pushvalue(self.state, metatable);
            ffi::lua_setmetatable(self.state, -2);
        }
    }
}
