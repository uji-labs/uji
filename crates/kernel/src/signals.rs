#[cfg(unix)]
use tokio::signal::unix::{Signal, SignalKind, signal};

#[cfg(unix)]
pub(crate) struct Signals {
    interrupt: Signal,
    terminate: Signal,
    hangup: Signal,
}

#[cfg(unix)]
impl Signals {
    pub(crate) fn new() -> std::io::Result<Self> {
        Ok(Self {
            interrupt: signal(SignalKind::interrupt())?,
            terminate: signal(SignalKind::terminate())?,
            hangup: signal(SignalKind::hangup())?,
        })
    }

    pub(crate) async fn next(&mut self) -> u8 {
        tokio::select! {
            _ = self.interrupt.recv() => 130,
            _ = self.terminate.recv() => 143,
            _ = self.hangup.recv() => 129,
        }
    }
}

#[cfg(not(unix))]
pub(crate) struct Signals;

#[cfg(not(unix))]
impl Signals {
    pub(crate) fn new() -> std::io::Result<Self> {
        Ok(Self)
    }

    pub(crate) async fn next(&mut self) -> u8 {
        std::future::pending().await
    }
}
