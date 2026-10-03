use std::borrow::Cow;
use std::ffi::c_int;
use std::fmt;

use mlua::{ExternalResult, Lua, LuaSerdeExt, Table, Value, ffi};
use serde::de::{DeserializeSeed, Deserializer, MapAccess, SeqAccess, Visitor};
use uji_macros::{constant, function, options};

const SLOTS: c_int = 3;
const WORD: f64 = 4_294_967_296.0;

#[function(json, raise)]
fn encode(value: &Value) -> Result<String, serde_json::Error> {
    serde_json::to_string(value)
}

#[options]
struct DecodeOptions {
    nulls: Option<bool>,
}

fn float(value: u64) -> f64 {
    let high = u32::try_from(value >> 32).unwrap_or(u32::MAX);
    let low = u32::try_from(value & u64::from(u32::MAX)).unwrap_or(0);
    f64::from(high) * WORD + f64::from(low)
}

#[derive(Clone, Copy)]
struct Push {
    state: *mut ffi::lua_State,
    array: c_int,
    nulls: bool,
}

#[allow(unsafe_code)]
impl Push {
    fn room<E: serde::de::Error>(self) -> Result<(), E> {
        if unsafe { ffi::lua_checkstack(self.state, SLOTS) } == 0 {
            return Err(E::custom("the JSON is nested too deeply"));
        }
        Ok(())
    }

    fn number(self, value: f64) {
        unsafe { ffi::lua_pushnumber(self.state, value) };
    }

    fn integer(self, value: i64) {
        match ffi::lua_Integer::try_from(value) {
            Ok(value) => unsafe { ffi::lua_pushinteger(self.state, value) },
            Err(_) if value < 0 => self.number(-float(value.unsigned_abs())),
            Err(_) => self.number(float(value.unsigned_abs())),
        }
    }

    fn string(self, value: &str) {
        unsafe { ffi::lua_pushlstring(self.state, value.as_ptr().cast(), value.len()) };
    }

    fn skipped(self) -> bool {
        unsafe { ffi::lua_isnil(self.state, -1) != 0 }
    }
}

impl<'de> DeserializeSeed<'de> for Push {
    type Value = ();

    fn deserialize<D: Deserializer<'de>>(self, deserializer: D) -> Result<(), D::Error> {
        deserializer.deserialize_any(self)
    }
}

#[allow(unsafe_code)]
impl<'de> Visitor<'de> for Push {
    type Value = ();

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("a JSON value")
    }

    fn visit_bool<E>(self, value: bool) -> Result<(), E> {
        unsafe { ffi::lua_pushboolean(self.state, c_int::from(value)) };
        Ok(())
    }

    fn visit_i64<E>(self, value: i64) -> Result<(), E> {
        self.integer(value);
        Ok(())
    }

    fn visit_u64<E>(self, value: u64) -> Result<(), E> {
        match i64::try_from(value) {
            Ok(value) => self.integer(value),
            Err(_) => self.number(float(value)),
        }
        Ok(())
    }

    fn visit_f64<E>(self, value: f64) -> Result<(), E> {
        self.number(value);
        Ok(())
    }

    fn visit_str<E>(self, value: &str) -> Result<(), E> {
        self.string(value);
        Ok(())
    }

    fn visit_unit<E>(self) -> Result<(), E> {
        if self.nulls {
            unsafe { ffi::lua_pushlightuserdata(self.state, std::ptr::null_mut()) };
        } else {
            unsafe { ffi::lua_pushnil(self.state) };
        }
        Ok(())
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<(), A::Error> {
        self.room()?;
        unsafe { ffi::lua_createtable(self.state, 0, 0) };
        let mut count: ffi::lua_Integer = 0;
        loop {
            self.room()?;
            if seq.next_element_seed(self)?.is_none() {
                break;
            }
            if self.skipped() {
                unsafe { ffi::lua_pop(self.state, 1) };
            } else {
                count += 1;
                unsafe { ffi::lua_rawseti(self.state, -2, count) };
            }
        }
        unsafe {
            ffi::lua_pushvalue(self.state, self.array);
            ffi::lua_setmetatable(self.state, -2);
        }
        Ok(())
    }

    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
        self.room()?;
        unsafe { ffi::lua_createtable(self.state, 0, 0) };
        loop {
            self.room()?;
            let Some(key) = map.next_key::<Cow<'de, str>>()? else {
                break;
            };
            self.string(&key);
            map.next_value_seed(self)?;
            if self.skipped() {
                unsafe { ffi::lua_pop(self.state, 2) };
            } else {
                unsafe { ffi::lua_rawset(self.state, -3) };
            }
        }
        Ok(())
    }
}

#[allow(unsafe_code)]
#[function(json)]
fn decode(lua: &Lua, text: &mlua::LuaString, opts: &DecodeOptions) -> mlua::Result<Value> {
    let bytes = text.as_bytes();
    let nulls = opts.nulls != Some(false);
    let mut failure = None;
    let value = unsafe {
        lua.exec_raw::<Value>(lua.array_metatable(), |state| {
            let array = ffi::lua_gettop(state);
            let mut deserializer = serde_json::Deserializer::from_slice(&bytes);
            let push = Push {
                state,
                array,
                nulls,
            };
            match push
                .deserialize(&mut deserializer)
                .and_then(|()| deserializer.end())
            {
                Ok(()) => ffi::lua_remove(state, array),
                Err(err) => {
                    ffi::lua_settop(state, array - 1);
                    failure = Some(err);
                }
            }
        })?
    };
    match failure {
        Some(err) => Err(err).into_lua_err(),
        None => Ok(value),
    }
}

#[function(json)]
fn array(lua: &Lua, table: Table) -> mlua::Result<Table> {
    table.set_metatable(Some(lua.array_metatable()))?;
    Ok(table)
}

#[constant(json)]
fn null(lua: &Lua) -> Value {
    lua.null()
}
