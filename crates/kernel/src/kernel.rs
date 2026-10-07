use std::path::PathBuf;
use std::process::{ExitCode, Termination};
use std::sync::Arc;
use std::time::Instant;

use ito::tty::{self, Terminal};
use mlua::{AppDataRef, AppDataRefMut, Function, Lua};
use tokio::runtime::Runtime;
use tokio::sync::Notify;
use tokio::task::LocalSet;

use crate::vm::{self, Sources};
use crate::{net, signals, task};

pub struct Options {
    pub sources: Vec<Sources>,
    pub entry: String,
    pub args: Vec<String>,
    pub terminal: Terminal,
    pub debug: bool,
}

pub struct Outcome {
    pub code: u8,
    pub errors: Vec<String>,
    signal: Option<i32>,
}

impl Termination for Outcome {
    fn report(self) -> ExitCode {
        if let Some(signal) = self.signal {
            signals::die(signal);
        }
        ExitCode::from(self.code)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("the kernel lost its state")]
    Lost,
    #[error("{0}")]
    Lua(#[from] mlua::Error),
}

pub(crate) struct Restart {
    pub(crate) args: Vec<String>,
    pub(crate) roots: Vec<PathBuf>,
    pub(crate) carry: Option<String>,
}

pub(crate) struct State {
    pub(crate) args: Vec<String>,
    pub(crate) layers: Vec<Sources>,
    pub(crate) roots: Vec<String>,
    pub(crate) carry: Option<String>,
    pub(crate) clipboard: Option<arboard::Clipboard>,
    pub(crate) started: Instant,
    pub(crate) pending: usize,
    pub(crate) collect: bool,
    pub(crate) exit: Option<u8>,
    pub(crate) signal: Option<i32>,
    pub(crate) restart: Option<Restart>,
    pub(crate) errors: Vec<String>,
    pub(crate) on_error: Option<Function>,
    wake: Arc<Notify>,
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

    pub(crate) fn report(lua: &Lua, message: &str) {
        let handler = Self::of(lua).ok().and_then(|state| state.on_error.clone());
        let delivered = handler.is_some_and(|handler| handler.call::<()>(message).is_ok());
        if !delivered && let Ok(mut state) = Self::of_mut(lua) {
            state.errors.push(message.to_string());
        }
    }

    pub(crate) fn wake(&self) {
        self.wake.notify_one();
    }

    pub(crate) fn stopping(&self) -> bool {
        self.exit.is_some() || self.restart.is_some()
    }

    fn stopped(&self) -> Option<u8> {
        if self.exit.is_some() {
            return self.exit;
        }
        (self.restart.is_some() || self.pending == 0).then_some(0)
    }
}

struct Life {
    code: u8,
    signal: Option<i32>,
    errors: Vec<String>,
    restart: Option<Restart>,
    terminal: Option<Terminal>,
}

pub fn run(options: Options) -> Outcome {
    drive(options).unwrap_or_else(|err| Outcome {
        code: 1,
        errors: vec![err.to_string()],
        signal: None,
    })
}

fn drive(options: Options) -> Result<Outcome, Error> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    runtime.spawn_blocking(net::warm);
    signals::force(&runtime)?;
    let Options {
        sources,
        entry,
        args,
        terminal,
        debug,
    } = options;
    let mut next = Restart {
        args,
        roots: Vec::new(),
        carry: None,
    };
    let mut terminal = Some(terminal);
    let mut errors = Vec::new();
    let (code, signal) = loop {
        let life = live(&runtime, (&sources, &entry, debug), next, terminal.take())?;
        errors.extend(life.errors);
        terminal = life.terminal;
        match life.restart {
            Some(restart) => next = restart,
            None => break (life.code, life.signal),
        }
    };
    tty::restore();
    drop(terminal);
    runtime.shutdown_background();
    Ok(Outcome {
        code,
        errors,
        signal,
    })
}

fn live(
    runtime: &Runtime,
    (sources, entry, debug): (&[Sources], &str, bool),
    boot: Restart,
    terminal: Option<Terminal>,
) -> Result<Life, Error> {
    let layers = vm::layers(sources, &boot.roots);
    let lua = vm::create(layers.clone(), &boot.roots, debug)?;
    if let Some(terminal) = terminal {
        tty::provide(&lua, terminal);
    }
    let wake = Arc::new(Notify::new());
    lua.set_app_data(State {
        args: boot.args.clone(),
        layers,
        roots: boot
            .roots
            .iter()
            .map(|root| root.display().to_string())
            .collect(),
        carry: boot.carry,
        clipboard: None,
        started: Instant::now(),
        pending: 0,
        collect: false,
        exit: None,
        signal: None,
        restart: None,
        errors: Vec::new(),
        on_error: None,
        wake: Arc::clone(&wake),
    });
    let local = LocalSet::new();
    let ran = local.block_on(runtime, start(&lua, entry, boot.args, &wake));
    drop(local);
    lua.gc_collect()?;
    let state = lua.remove_app_data::<State>().ok_or(Error::Lost)?;
    let code = ran?;
    Ok(Life {
        code,
        signal: state.signal,
        terminal: tty::reclaim(&lua),
        errors: state.errors,
        restart: state.restart,
    })
}

async fn start(lua: &Lua, entry: &str, args: Vec<String>, wake: &Notify) -> Result<u8, Error> {
    signals::listen(lua)?;
    let main: Function = vm::require(lua, entry)?;
    task::start(lua, &main, lua.create_sequence_from(args)?)?;
    loop {
        wake.notified().await;
        if let Some(code) = State::of(lua)?.stopped() {
            return Ok(code);
        }
        let collect = std::mem::take(&mut State::of_mut(lua)?.collect);
        if collect {
            lua.gc_collect()?;
        }
    }
}
