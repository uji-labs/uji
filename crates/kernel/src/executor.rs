use std::time::Duration;

use futures_util::future::{AbortHandle, Abortable};
use mlua::{Function, IntoLuaMulti, Lua, MultiValue, Table, UserData, UserDataMethods};

use crate::io;
use crate::kernel::State;

pub(crate) struct Task(AbortHandle);

impl UserData for Task {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("cancel", |_, task, ()| {
            task.0.abort();
            Ok(())
        });
    }
}

pub(crate) fn spawn(lua: &Lua, function: &Function, args: impl IntoLuaMulti) -> mlua::Result<Task> {
    let call = function.call_async::<()>(args);
    let (handle, registration) = AbortHandle::new_pair();
    let owner = lua.clone();
    let scheduler = State::of(lua)?.scheduler.clone();
    scheduler
        .schedule(async move {
            match Abortable::new(call, registration).await {
                Ok(Err(err)) => State::report(&owner, &err.to_string()),
                Err(_) => {
                    let _ = owner.gc_collect();
                }
                Ok(Ok(())) => {}
            }
            finish(&owner);
        })
        .map_err(|_| mlua::Error::runtime("the executor has stopped"))?;
    State::of_mut(lua)?.pending += 1;
    Ok(Task(handle))
}

fn finish(lua: &Lua) {
    if let Ok(mut state) = State::of_mut(lua) {
        state.pending = state.pending.saturating_sub(1);
    }
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let task = lua.create_table()?;
    task.set(
        "spawn",
        lua.create_function(|lua, (function, args): (Function, MultiValue)| {
            spawn(lua, &function, args)
        })?,
    )?;
    task.set(
        "on_error",
        lua.create_function(|lua, handler: Option<Function>| {
            State::of_mut(lua)?.on_error = handler;
            Ok(())
        })?,
    )?;
    Ok(task)
}

pub(crate) fn sleep(lua: &Lua) -> mlua::Result<Function> {
    lua.create_async_function(|lua, seconds: f64| async move {
        let duration = Duration::try_from_secs_f64(seconds)
            .map_err(|_| mlua::Error::runtime("sleep needs a number of seconds"))?;
        io::run(io::handle(&lua)?, async move {
            tokio::time::sleep(duration).await;
        })
        .await
    })
}
