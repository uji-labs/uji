mod input;
mod real;
mod screen;
mod virtual_screen;

use crossterm::event::Event;
use mlua::{AnyUserData, IntoLuaMulti, Lua, Table};
use tokio::sync::{mpsc, watch};

use crate::kernel::State;

pub enum Terminal {
    Real,
    Virtual(VirtualTerminal),
}

pub(crate) enum Tty {
    Fresh(Terminal),
    Opened(screen::Screen, input::Input),
}

pub(crate) fn reclaim(screen: &AnyUserData, input: &AnyUserData) -> Option<Tty> {
    Some(Tty::Opened(
        screen.take::<screen::Screen>().ok()?,
        input.take::<input::Input>().ok()?,
    ))
}

pub struct VirtualTerminal {
    events: mpsc::UnboundedReceiver<Event>,
    frames: watch::Sender<Vec<String>>,
    size: watch::Receiver<(u16, u16)>,
}

pub struct VirtualHandle {
    events: mpsc::UnboundedSender<Event>,
    frames: watch::Receiver<Vec<String>>,
    size: watch::Sender<(u16, u16)>,
}

impl VirtualHandle {
    pub fn send(&self, event: Event) -> bool {
        self.events.send(event).is_ok()
    }

    pub fn resize(&self, width: u16, height: u16) -> bool {
        self.size.send((width, height)).is_ok() && self.send(Event::Resize(width, height))
    }

    pub fn frame(&self) -> Vec<String> {
        self.frames.borrow().clone()
    }

    pub fn frames(&self) -> watch::Receiver<Vec<String>> {
        self.frames.clone()
    }
}

pub fn virtual_terminal(width: u16, height: u16) -> (VirtualTerminal, VirtualHandle) {
    let (sender, events) = mpsc::unbounded_channel();
    let (published, frames) = watch::channel(Vec::new());
    let (resized, size) = watch::channel((width, height));
    (
        VirtualTerminal {
            events,
            frames: published,
            size,
        },
        VirtualHandle {
            events: sender,
            frames,
            size: resized,
        },
    )
}

pub(crate) fn restore() {
    real::restore();
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let tty = lua.create_table()?;
    tty.set(
        "open",
        lua.create_function(|lua, ()| {
            let terminal = State::of_mut(lua)?
                .terminal
                .take()
                .ok_or_else(|| mlua::Error::runtime("the terminal is already open"))?;
            let (screen, input) = match terminal {
                Tty::Fresh(Terminal::Real) => real::open()?,
                Tty::Fresh(Terminal::Virtual(terminal)) => virtual_screen::open(terminal)?,
                Tty::Opened(screen, input) => (screen, input),
            };
            let screen = lua.create_userdata(screen)?;
            let input = lua.create_userdata(input)?;
            State::of_mut(lua)?.opened = Some((screen.clone(), input.clone()));
            (screen, input).into_lua_multi(lua)
        })?,
    )?;
    Ok(tty)
}
