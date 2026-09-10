pub mod command;
mod convert;
pub mod event;
pub mod handlers;
pub mod llm;
pub mod model;
pub mod schedule;
pub mod scheduled;
pub mod state;
pub mod status;
pub mod tools;
pub mod window;

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;

use mlua::{Function, Lua, Table, Value};

use crate::state::UiState;

use self::handlers::Handlers;
use self::scheduled::Scheduled;
use self::tools::LuaTool;

pub struct Api {
    state: Rc<RefCell<UiState>>,
    scheduled: Scheduled,
    handlers: RefCell<Handlers>,
    commands: RefCell<HashMap<String, Function>>,
    tools: RefCell<HashMap<String, LuaTool>>,
}

impl Api {
    pub fn new(state: Rc<RefCell<UiState>>) -> Rc<Self> {
        Rc::new(Self {
            state,
            scheduled: Scheduled::default(),
            handlers: RefCell::default(),
            commands: RefCell::default(),
            tools: RefCell::default(),
        })
    }

    pub fn state(&self) -> Rc<RefCell<UiState>> {
        self.state.clone()
    }

    pub fn scheduled(&self) -> &Scheduled {
        &self.scheduled
    }

    pub fn commands(&self) -> &RefCell<HashMap<String, Function>> {
        &self.commands
    }

    pub fn lua_tools(&self) -> &RefCell<HashMap<String, LuaTool>> {
        &self.tools
    }

    pub(crate) fn handlers(&self) -> &RefCell<Handlers> {
        &self.handlers
    }

    pub fn dispatch(&self, event: &str, ctx: &Table) {
        for handler in self.handlers.borrow().get(event) {
            if let Err(err) = handler.call::<()>((event, ctx.clone())) {
                eprintln!("uji: handler error for {event}: {err}");
            }
        }
    }

    pub fn dispatch_tool(&self, event: &str, event_table: &Table) -> Option<Value> {
        for handler in self.handlers.borrow().get(event) {
            match handler.call::<Value>(event_table.clone()) {
                Ok(value) if !value.is_nil() => return Some(value),
                Ok(_) => {}
                Err(err) => eprintln!("uji: {event} handler error: {err}"),
            }
        }
        None
    }
}

pub fn register(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Table> {
    let uji = lua.create_table()?;

    let ui = lua.create_table()?;
    ui.set("open_win", window::open_win(lua, api)?)?;
    ui.set("close_win", window::close_win(lua, api)?)?;
    ui.set("set_lines", window::set_lines(lua, api)?)?;
    ui.set("clear", window::clear(lua, api)?)?;
    ui.set("set_size", window::set_size(lua, api)?)?;
    ui.set("set_title", window::set_title(lua, api)?)?;
    ui.set("configure", window::configure(lua, api)?)?;
    uji.set("ui", ui)?;

    let llm = lua.create_table()?;
    llm.set("current_provider", llm::current_provider(lua, api)?)?;
    llm.set("current_model", llm::current_model(lua, api)?)?;
    uji.set("llm", llm)?;

    let status = lua.create_table()?;
    status.set("provider", status::provider(lua, api)?)?;
    status.set("model", status::model(lua, api)?)?;
    status.set("state", status::state(lua, api)?)?;
    status.set("elapsed", status::elapsed(lua, api)?)?;
    status.set("loader_frame", status::loader_frame(lua, api)?)?;
    uji.set("status", status)?;

    uji.set("schedule", schedule::schedule(lua, api)?)?;
    uji.set("on", event::on(lua, api)?)?;
    uji.set("emit", event::emit(lua, api)?)?;
    uji.set("notify", event::notify(lua)?)?;
    uji.set("command", command::command(lua, api)?)?;

    let tool = lua.create_table()?;
    tool.set("register", tools::register(lua, api)?)?;
    tool.set("unregister", tools::unregister(lua, api)?)?;
    uji.set("tool", tool)?;

    Ok(uji)
}
