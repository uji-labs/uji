use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const READ_TIMEOUT: Duration = Duration::from_secs(150);

use calloop::EventLoop;
use calloop::futures::Scheduler;
use mlua::{AppDataRef, AppDataRefMut, Function, Lua};
use tokio::runtime::Handle;

use crate::executor;
use crate::tty::{self, Terminal};
use crate::vm::{self, Sources};

pub struct Options {
    pub sources: Sources,
    pub entry: String,
    pub args: Vec<String>,
    pub terminal: Terminal,
}

pub struct Outcome {
    pub code: u8,
    pub errors: Vec<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Loop(#[from] calloop::Error),
    #[error("{0}")]
    Lua(#[from] mlua::Error),
}

pub(crate) struct State {
    pub(crate) io: Handle,
    pub(crate) scheduler: Scheduler<()>,
    pub(crate) client: Arc<OnceLock<reqwest::Client>>,
    pub(crate) terminal: Option<Terminal>,
    pub(crate) started: Instant,
    pub(crate) pending: usize,
    pub(crate) exit: Option<u8>,
    pub(crate) errors: Vec<String>,
    pub(crate) on_error: Option<Function>,
    pub(crate) clipboard: Option<arboard::Clipboard>,
}

impl State {
    pub(crate) fn of(lua: &Lua) -> mlua::Result<AppDataRef<'_, Self>> {
        lua.app_data_ref::<Self>()
            .ok_or_else(|| mlua::Error::runtime("the kernel is not running"))
    }

    pub(crate) fn of_mut(lua: &Lua) -> mlua::Result<AppDataRefMut<'_, Self>> {
        lua.app_data_mut::<Self>()
            .ok_or_else(|| mlua::Error::runtime("the kernel is not running"))
    }

    pub(crate) fn client(&self) -> reqwest::Client {
        self.client.get_or_init(http_client).clone()
    }

    pub(crate) fn report(lua: &Lua, message: &str) {
        let handler = Self::of(lua).ok().and_then(|state| state.on_error.clone());
        let delivered = handler.is_some_and(|handler| handler.call::<()>(message).is_ok());
        if !delivered && let Ok(mut state) = Self::of_mut(lua) {
            state.errors.push(message.to_string());
        }
    }
}

fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .read_timeout(READ_TIMEOUT)
        .build()
        .unwrap_or_default()
}

pub fn run(options: Options) -> Outcome {
    drive(options).unwrap_or_else(|err| Outcome {
        code: 1,
        errors: vec![err.to_string()],
    })
}

fn drive(options: Options) -> Result<Outcome, Error> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    let mut event_loop: EventLoop<'static, ()> = EventLoop::try_new()?;
    let (executor, scheduler) = calloop::futures::executor::<()>()?;
    event_loop
        .handle()
        .insert_source(executor, |(), (), ()| {})
        .map_err(|err| err.error)?;
    let client = Arc::new(OnceLock::new());
    let warming = Arc::clone(&client);
    drop(runtime.spawn_blocking(move || warming.get_or_init(http_client).clone()));
    let lua = vm::create(options.sources)?;
    lua.set_app_data(State {
        io: runtime.handle().clone(),
        scheduler,
        client,
        terminal: Some(options.terminal),
        started: Instant::now(),
        pending: 0,
        exit: None,
        errors: Vec::new(),
        on_error: None,
        clipboard: None,
    });
    let main = vm::entry(&lua, &options.entry)?;
    executor::spawn(&lua, &main, lua.create_sequence_from(options.args)?)?;
    let code = turn(&lua, &mut event_loop)?;
    tty::restore();
    let errors = lua
        .remove_app_data::<State>()
        .map(|state| state.errors)
        .unwrap_or_default();
    drop(event_loop);
    drop(lua);
    runtime.shutdown_background();
    Ok(Outcome { code, errors })
}

fn turn(lua: &Lua, event_loop: &mut EventLoop<'static, ()>) -> Result<u8, Error> {
    loop {
        event_loop.dispatch(None, &mut ())?;
        let state = State::of(lua)?;
        if let Some(code) = state.exit {
            return Ok(code);
        }
        if state.pending == 0 {
            return Ok(0);
        }
    }
}
