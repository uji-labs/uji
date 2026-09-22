pub mod action;
pub mod agent;
mod bind;
pub mod command;
mod convert;
pub mod event;
pub mod handlers;
pub mod input;
pub mod job;
pub mod json;
pub mod keymap;
pub mod llm;
pub mod modal;
pub mod pick;
pub mod provider;
pub mod request;

pub mod registry;
pub mod schedule;
pub mod scheduled;
pub mod session;

pub mod status;
pub mod tools;
pub mod window;

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::rc::Rc;

use mlua::{Lua, Table, Value};

use self::action::Actions;
use uji_agent::session::conversation::Shared;
use uji_ui::state::UiState;

use self::handlers::Handlers;
use self::input::{Capture, Composer};
use self::job::Jobs;
use self::registry::Registry;
use self::scheduled::Scheduled;
use self::session::SessionState;
use self::tools::LuaTool;
use uji_agent::llm::Catalog;
use uji_ui::keymap::Keymap;

pub struct Api {
    state: Rc<RefCell<UiState>>,
    scheduled: Scheduled,
    handlers: RefCell<Handlers>,
    commands: RefCell<HashMap<String, command::LuaCommand>>,
    tools: RefCell<BTreeMap<String, LuaTool>>,
    providers: RefCell<Catalog>,
    keymap: RefCell<Keymap>,
    packs: RefCell<Vec<PathBuf>>,
    notices: RefCell<Vec<String>>,
    jobs: RefCell<Jobs>,
    composer: Composer,
    capture: Capture,
    session_state: SessionState,
    requests: RefCell<Vec<request::Request>>,
    pick: RefCell<pick::Pick>,
    access: RefCell<tools::Access>,
    segments: Registry,
    agent_context: Registry,
    actions: Actions,
}

impl Api {
    pub fn new(state: Rc<RefCell<UiState>>, conversation: Shared) -> Rc<Self> {
        Rc::new(Self {
            state,
            scheduled: Scheduled::default(),
            handlers: RefCell::default(),
            commands: RefCell::default(),
            access: RefCell::default(),
            tools: RefCell::default(),
            providers: RefCell::default(),
            keymap: RefCell::default(),
            packs: RefCell::default(),
            notices: RefCell::default(),
            jobs: RefCell::default(),
            composer: Composer::default(),
            capture: Capture::default(),
            session_state: SessionState::new(conversation),
            requests: RefCell::default(),
            pick: RefCell::default(),
            segments: Registry::default(),
            agent_context: Registry::default(),
            actions: Actions::default(),
        })
    }

    pub fn state(&self) -> Rc<RefCell<UiState>> {
        Rc::clone(&self.state)
    }

    pub fn scheduled(&self) -> &Scheduled {
        &self.scheduled
    }

    pub fn commands(&self) -> &RefCell<HashMap<String, command::LuaCommand>> {
        &self.commands
    }

    pub fn lua_tools(&self) -> &RefCell<BTreeMap<String, LuaTool>> {
        &self.tools
    }

    pub fn providers(&self) -> &RefCell<Catalog> {
        &self.providers
    }

    pub fn keymap(&self) -> &RefCell<Keymap> {
        &self.keymap
    }

    pub fn packs(&self) -> &RefCell<Vec<PathBuf>> {
        &self.packs
    }

    pub fn notify(&self, message: String) {
        self.notices.borrow_mut().push(message);
    }

    pub fn capture(&self) -> &Capture {
        &self.capture
    }

    pub fn composer(&self) -> &Composer {
        &self.composer
    }

    /// Ask the runtime to act on the next tick.
    pub fn request(&self, request: request::Request) {
        self.requests.borrow_mut().push(request);
    }

    /// The open picker's callbacks and query generation.
    pub fn pick(&self) -> &RefCell<pick::Pick> {
        &self.pick
    }

    pub fn take_requests(&self) -> Vec<request::Request> {
        std::mem::take(&mut *self.requests.borrow_mut())
    }

    pub fn segments(&self) -> &Registry {
        &self.segments
    }

    pub fn actions(&self) -> &Actions {
        &self.actions
    }

    pub fn agent_context(&self) -> &Registry {
        &self.agent_context
    }

    pub fn session(&self) -> &SessionState {
        &self.session_state
    }

    pub fn jobs(&self) -> &RefCell<Jobs> {
        &self.jobs
    }

    pub fn take_notices(&self) -> Vec<String> {
        let mut notices = std::mem::take(&mut *self.notices.borrow_mut());
        notices.extend(self.state.borrow_mut().take_notices());
        notices
    }

    pub(crate) fn handlers(&self) -> &RefCell<Handlers> {
        &self.handlers
    }

    pub fn dispatch(&self, event: &str, payload: &Table) {
        self.run(event, payload, Policy::All);
    }

    /// Where file tools may reach, and whether they are confined to it.
    pub fn access(&self) -> &RefCell<tools::Access> {
        &self.access
    }

    pub fn has_handler(&self, event: &str) -> bool {
        self.handlers.borrow().has(event)
    }

    pub fn ask(&self, event: &str, payload: &Table) -> Option<Value> {
        self.run(event, payload, Policy::FirstAnswer)
    }

    fn run(&self, event: &str, payload: &Table, policy: Policy) -> Option<Value> {
        let _ = payload.set("event", event);
        for handler in self.handlers.borrow().get(event) {
            match handler.call::<Value>(payload.clone()) {
                Ok(value) if policy == Policy::FirstAnswer && !value.is_nil() => {
                    return Some(value);
                }
                Ok(_) => {}
                Err(err) => self.notify(format!("{event} handler error: {err}")),
            }
        }
        None
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Policy {
    All,
    FirstAnswer,
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
    ui.set("exec", window::exec(lua, api)?)?;
    ui.set("select", modal::select(lua, api)?)?;
    ui.set("pick", modal::pick(lua, api)?)?;
    ui.set("pick_items", modal::pick_items(lua, api)?)?;
    ui.set("prompt", modal::prompt(lua, api)?)?;
    uji.set("ui", ui)?;

    let llm = lua.create_table()?;
    llm.set("current_provider", llm::current_provider(lua, api)?)?;
    llm.set("current_model", llm::current_model(lua, api)?)?;
    uji.set("llm", llm)?;

    let status = lua.create_table()?;
    status.set("provider", status::provider(lua, api)?)?;
    status.set("model", status::model(lua, api)?)?;
    status.set("effort", status::effort(lua, api)?)?;
    status.set("context", status::context(lua, api)?)?;
    status.set("queue", status::queue(lua, api)?)?;
    status.set("state", status::state(lua, api)?)?;
    status.set("elapsed", status::elapsed(lua, api)?)?;
    status.set("loader_frame", status::loader_frame(lua, api)?)?;
    status.set("add", status::add(lua, api)?)?;
    status.set("remove", status::remove(lua, api)?)?;
    status.set("segments", status::segments(lua, api)?)?;
    uji.set("status", status)?;

    uji.set("json", json::register(lua, api)?)?;
    uji.set("schedule", schedule::schedule(lua, api)?)?;
    uji.set("on", event::on(lua, api)?)?;
    uji.set("off", event::off(lua, api)?)?;
    uji.set("emit", event::emit(lua, api)?)?;
    uji.set("notify", event::notify(lua, api)?)?;
    uji.set("command", command::command(lua, api)?)?;

    let tool = lua.create_table()?;
    tool.set("register", tools::register(lua, api)?)?;
    tool.set("unregister", tools::unregister(lua, api)?)?;
    tool.set("roots", tools::roots(lua, api)?)?;
    tool.set("list_roots", tools::list_roots(lua, api)?)?;
    tool.set("disable", tools::disable(lua, api)?)?;
    tool.set("enable", tools::enable(lua, api)?)?;
    tool.set("confine", tools::confine(lua, api)?)?;
    uji.set("tool", tool)?;

    uji.set("agent", agent::register(lua, api)?)?;
    uji.set("action", action::register(lua, api)?)?;
    uji.set("keymap", keymap::register(lua, api)?)?;
    uji.set("provider", provider::register(lua, api)?)?;
    uji.set("job", job::register(lua, api)?)?;
    uji.set("input", input::register(lua, api)?)?;
    uji.set("session", session::register(lua, api)?)?;

    Ok(uji)
}
