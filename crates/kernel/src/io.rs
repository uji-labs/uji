use std::fmt::Display;
use std::future::Future;
use std::time::Duration;

use mlua::serde::SerializeOptions;
use mlua::{
    BString, Function, IntoLua, IntoLuaMulti, Lua, LuaSerdeExt, LuaString, MultiValue, Value,
};
use serde::Serialize;
use tokio::task::{AbortHandle, JoinError};
use uji_macros::function;

pub(crate) struct Abort(pub(crate) AbortHandle);

impl Drop for Abort {
    fn drop(&mut self) {
        self.0.abort();
    }
}

#[derive(Debug, thiserror::Error)]
pub(crate) enum Blocked<E> {
    #[error("{0}")]
    Failed(E),
    #[error("{0}")]
    Stopped(#[from] JoinError),
}

pub(crate) async fn blocking<T: Send + 'static, E: Send + 'static>(
    work: impl FnOnce() -> Result<T, E> + Send + 'static,
) -> Result<T, Blocked<E>> {
    tokio::task::spawn_blocking(work)
        .await?
        .map_err(Blocked::Failed)
}

pub(crate) fn reason(err: &mlua::Error) -> String {
    match err {
        mlua::Error::CallbackError { cause, .. } => reason(cause),
        mlua::Error::RuntimeError(text) => text
            .split_once("\nstack traceback:")
            .map_or(text.as_str(), |(head, _)| head)
            .to_string(),
        other => other.to_string(),
    }
}

#[function]
fn traceback(lua: &Lua, level: Option<usize>) -> mlua::Result<String> {
    Ok(lua.traceback(None, level.unwrap_or(1))?.to_string_lossy())
}

#[function]
fn message(lua: &Lua, value: Value) -> mlua::Result<String> {
    if let Value::Error(err) = &value {
        return Ok(reason(err));
    }
    let text: LuaString = lua.globals().get::<Function>("tostring")?.call(value)?;
    Ok(text.to_string_lossy())
}

pub(crate) struct Script {
    pub(crate) name: &'static str,
    pub(crate) source: &'static str,
    pub(crate) native: fn(&Lua) -> mlua::Result<Function>,
}

impl IntoLua for Script {
    fn into_lua(self, lua: &Lua) -> mlua::Result<Value> {
        lua.load(self.source)
            .set_name(format!("={}", self.name))
            .call((self.native)(lua)?)
    }
}

pub(crate) fn to_lua(lua: &Lua, value: &impl Serialize) -> mlua::Result<Value> {
    lua.to_value_with(
        value,
        SerializeOptions::new()
            .serialize_none_to_null(false)
            .serialize_unit_to_null(false),
    )
}

pub(crate) fn settle<T: IntoLuaMulti, E: Display>(
    lua: &Lua,
    result: Result<T, E>,
) -> mlua::Result<MultiValue> {
    match result {
        Ok(value) => value.into_lua_multi(lua),
        Err(err) => (Value::Nil, err.to_string()).into_lua_multi(lua),
    }
}

pub(crate) enum Line {
    Text(BString),
    End,
    Late,
}

impl Line {
    pub(crate) async fn within<E>(
        limit: Option<Duration>,
        read: impl Future<Output = Result<Option<Vec<u8>>, E>>,
    ) -> Result<Self, E> {
        match limit {
            None => read.await.map(Self::from),
            Some(limit) => tokio::time::timeout(limit, read)
                .await
                .map_or(Ok(Self::Late), |read| read.map(Self::from)),
        }
    }
}

impl From<Option<Vec<u8>>> for Line {
    fn from(line: Option<Vec<u8>>) -> Self {
        line.map_or(Self::End, |text| Self::Text(text.into()))
    }
}

impl IntoLuaMulti for Line {
    fn into_lua_multi(self, lua: &Lua) -> mlua::Result<MultiValue> {
        match self {
            Self::Text(text) => text.into_lua_multi(lua),
            Self::End => Ok(MultiValue::new()),
            Self::Late => false.into_lua_multi(lua),
        }
    }
}
