use std::future::Future;
use std::panic::AssertUnwindSafe;
use std::pin::pin;
use std::task::Poll;
use std::time::Duration;

use futures_util::FutureExt;
use futures_util::future::{self, AbortHandle, Abortable, Either};
use mlua::{Function, IntoLuaMulti, Lua, MultiValue, Value, Variadic};
use uji_macros::{function, methods};

use crate::io;
use crate::kernel::State;

pub(crate) struct Task(AbortHandle);

#[methods]
impl Task {
    fn cancel(&self) {
        self.0.abort();
    }
}

pub(crate) fn start(lua: &Lua, function: &Function, args: impl IntoLuaMulti) -> mlua::Result<Task> {
    let call = function.call_async::<()>(args);
    let (handle, registration) = AbortHandle::new_pair();
    let owner = lua.clone();
    State::of_mut(lua)?.pending += 1;
    tokio::task::spawn_local(async move {
        let mut call = pin!(Abortable::new(call, registration));
        let ran = std::future::poll_fn(|cx| {
            if State::of(&owner).is_ok_and(|state| state.stopping()) {
                return Poll::Pending;
            }
            call.as_mut().poll(cx)
        });
        let cancelled = match AssertUnwindSafe(ran).catch_unwind().await {
            Ok(Ok(Err(err))) => {
                State::report(&owner, &io::reason(&err));
                false
            }
            Ok(Ok(Ok(()))) => false,
            Ok(Err(_)) => true,
            Err(_) => {
                State::report(&owner, "a task panicked");
                if let Ok(mut state) = State::of_mut(&owner) {
                    state.exit = Some(1);
                }
                false
            }
        };
        finish(&owner, cancelled);
    });
    Ok(Task(handle))
}

fn finish(lua: &Lua, cancelled: bool) {
    if let Ok(mut state) = State::of_mut(lua) {
        state.pending = state.pending.saturating_sub(1);
        state.collect |= cancelled;
        state.wake();
    }
}

fn duration(seconds: f64, what: &str) -> mlua::Result<Option<Duration>> {
    if seconds.is_infinite() && seconds.is_sign_positive() {
        return Ok(None);
    }
    Duration::try_from_secs_f64(seconds)
        .map(Some)
        .map_err(|_| mlua::Error::runtime(format!("{what} needs a number of seconds")))
}

async fn wait(limit: Option<Duration>) {
    match limit {
        None => future::pending().await,
        Some(limit) if limit.is_zero() => tokio::task::yield_now().await,
        Some(limit) => tokio::time::sleep(limit).await,
    }
}

#[function(task)]
fn spawn(lua: &Lua, function: &Function, args: MultiValue) -> mlua::Result<Task> {
    start(lua, function, args)
}

#[function(task)]
fn on_error(state: &mut State, handler: Option<Function>) {
    state.on_error = handler;
}

#[function]
async fn sleep(seconds: f64) -> mlua::Result<()> {
    wait(duration(seconds, "sleep")?).await;
    Ok(())
}

#[function(task)]
async fn race(functions: Variadic<Function>) -> mlua::Result<MultiValue> {
    if functions.is_empty() {
        return Err(mlua::Error::runtime("race needs at least one function"));
    }
    let calls = functions
        .iter()
        .map(|function| Box::pin(function.call_async::<MultiValue>(())));
    let (outcome, index, _) = future::select_all(calls).await;
    let mut values = outcome?;
    let position = i64::try_from(index.saturating_add(1)).unwrap_or(i64::MAX);
    values.push_front(Value::Integer(position));
    Ok(values)
}

#[function(task)]
async fn timeout(seconds: f64, function: Function) -> mlua::Result<MultiValue> {
    let timer = wait(duration(seconds, "timeout")?);
    let call = function.call_async::<MultiValue>(());
    match future::select(pin!(call), pin!(timer)).await {
        Either::Left((values, _)) => {
            let mut values = values?;
            values.push_front(Value::Boolean(true));
            Ok(values)
        }
        Either::Right(((), _)) => Ok(MultiValue::from_vec(vec![Value::Boolean(false)])),
    }
}
