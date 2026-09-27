use std::fmt::Display;
use std::future::Future;

use mlua::{IntoLuaMulti, Lua, MultiValue, Value};
use tokio::runtime::Handle;
use tokio::task::AbortHandle;

use crate::kernel::State;

pub(crate) struct Abort(pub(crate) AbortHandle);

impl Drop for Abort {
    fn drop(&mut self) {
        self.0.abort();
    }
}

pub(crate) fn handle(lua: &Lua) -> mlua::Result<Handle> {
    Ok(State::of(lua)?.io.clone())
}

pub(crate) async fn run<T: Send + 'static>(
    io: Handle,
    work: impl Future<Output = T> + Send + 'static,
) -> mlua::Result<T> {
    let task = io.spawn(work);
    let guard = Abort(task.abort_handle());
    let outcome = task.await;
    drop(guard);
    outcome.map_err(mlua::Error::external)
}

pub(crate) async fn blocking<T: Send + 'static>(
    io: Handle,
    work: impl FnOnce() -> T + Send + 'static,
) -> mlua::Result<T> {
    io.spawn_blocking(work).await.map_err(mlua::Error::external)
}

pub(crate) fn failure(lua: &Lua, err: &impl Display) -> mlua::Result<MultiValue> {
    (Value::Nil, err.to_string()).into_lua_multi(lua)
}

pub(crate) fn settle<T: IntoLuaMulti, E: Display>(
    lua: &Lua,
    result: Result<T, E>,
) -> mlua::Result<MultiValue> {
    match result {
        Ok(value) => value.into_lua_multi(lua),
        Err(err) => failure(lua, &err),
    }
}
