use mlua::Lua;
#[cfg(unix)]
use nix::sys::signal::{SigHandler, Signal, raise};
use tokio::runtime::Runtime;
#[cfg(unix)]
use tokio::signal::unix::{SignalKind, signal};

#[cfg(unix)]
use crate::kernel::State;

#[cfg(unix)]
const STOPS: [(SignalKind, u8); 3] = [
    (SignalKind::interrupt(), 130),
    (SignalKind::terminate(), 143),
    (SignalKind::hangup(), 129),
];

#[cfg(unix)]
pub(crate) fn listen(lua: &Lua) -> std::io::Result<()> {
    for (kind, code) in STOPS {
        let mut stream = signal(kind)?;
        let owner = lua.clone();
        tokio::task::spawn_local(async move {
            if stream.recv().await.is_some()
                && let Ok(mut state) = State::of_mut(&owner)
            {
                state.exit = Some(code);
                state.signal = Some(kind.as_raw_value());
                state.wake();
            }
        });
    }
    Ok(())
}

#[cfg(unix)]
pub(crate) fn force(runtime: &Runtime) -> std::io::Result<()> {
    let _context = runtime.enter();
    for (kind, _) in STOPS {
        let mut stream = signal(kind)?;
        runtime.spawn(async move {
            if stream.recv().await.is_some() && stream.recv().await.is_some() {
                die(kind.as_raw_value());
            }
        });
    }
    Ok(())
}

#[cfg(unix)]
#[allow(unsafe_code)]
pub(crate) fn die(signal: i32) {
    ito::tty::restore();
    if let Ok(stop) = Signal::try_from(signal)
        && unsafe { nix::sys::signal::signal(stop, SigHandler::SigDfl) }.is_ok()
    {
        let _ = raise(stop);
    }
}

#[cfg(not(unix))]
pub(crate) fn listen(_: &Lua) -> std::io::Result<()> {
    Ok(())
}

#[cfg(not(unix))]
pub(crate) fn force(_: &Runtime) -> std::io::Result<()> {
    Ok(())
}

#[cfg(not(unix))]
pub(crate) fn die(_: i32) {}
