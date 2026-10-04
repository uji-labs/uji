use std::borrow::Cow;
use std::ffi::c_int;
use std::fmt;

use mlua::{ExternalResult, Lua, LuaSerdeExt, Table, Value};
use serde::de::{DeserializeSeed, Deserializer, Error, MapAccess, SeqAccess, Visitor};
use serde_json::Number;
use uji_macros::{constant, function, options};

use crate::utils::lua::stack::{self, Stack};

#[function(json, raise)]
fn encode(value: &Value) -> Result<String, serde_json::Error> {
    serde_json::to_string(value)
}

#[options]
struct DecodeOptions {
    nulls: Option<bool>,
}

#[derive(Clone, Copy)]
struct Decoder<'a> {
    stack: &'a Stack,
    array_metatable: c_int,
    nulls: bool,
}

impl Decoder<'_> {
    fn table<E: Error>(self) -> Result<(), E> {
        if !self.stack.reserve() {
            return Err(E::custom("the JSON is nested too deeply"));
        }
        self.stack.table(0);
        Ok(())
    }
}

impl<'de> DeserializeSeed<'de> for Decoder<'_> {
    type Value = ();

    fn deserialize<D: Deserializer<'de>>(self, deserializer: D) -> Result<(), D::Error> {
        deserializer.deserialize_any(self)
    }
}

impl<'de> Visitor<'de> for Decoder<'_> {
    type Value = ();

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("a JSON value")
    }

    fn visit_bool<E: Error>(self, value: bool) -> Result<(), E> {
        self.stack.boolean(value);
        Ok(())
    }

    fn visit_i64<E: Error>(self, value: i64) -> Result<(), E> {
        self.stack.integer(value);
        Ok(())
    }

    fn visit_u64<E: Error>(self, value: u64) -> Result<(), E> {
        match i64::try_from(value) {
            Ok(value) => self.visit_i64(value),
            Err(_) => self.visit_f64(Number::from(value).as_f64().unwrap_or_default()),
        }
    }

    fn visit_f64<E: Error>(self, value: f64) -> Result<(), E> {
        self.stack.number(value);
        Ok(())
    }

    fn visit_str<E: Error>(self, value: &str) -> Result<(), E> {
        self.stack.string(value);
        Ok(())
    }

    fn visit_unit<E: Error>(self) -> Result<(), E> {
        if self.nulls {
            self.stack.null();
        } else {
            self.stack.nil();
        }
        Ok(())
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<(), A::Error> {
        self.table()?;
        let mut length = 0;
        while seq.next_element_seed(self)?.is_some() {
            length += 1;
            self.stack.set_index(length);
        }
        self.stack.set_metatable(self.array_metatable);
        Ok(())
    }

    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
        self.table()?;
        while let Some(key) = map.next_key::<Cow<'de, str>>()? {
            self.stack.string(&key);
            map.next_value_seed(self)?;
            self.stack.set_field();
        }
        Ok(())
    }
}

#[function(json)]
fn decode(lua: &Lua, text: &mlua::LuaString, opts: &DecodeOptions) -> mlua::Result<Value> {
    let bytes = text.as_bytes();
    let mut deserializer = serde_json::Deserializer::from_slice(&bytes);
    let nulls = opts.nulls != Some(false);
    stack::build(lua, lua.array_metatable(), |stack| {
        let decoder = Decoder {
            stack,
            array_metatable: stack.top(),
            nulls,
        };
        decoder
            .deserialize(&mut deserializer)
            .and_then(|()| deserializer.end())
            .into_lua_err()
    })
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
