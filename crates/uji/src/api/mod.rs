pub mod action;
pub mod agent;
pub(crate) mod bind;
pub mod callbacks;
pub mod command;
pub mod context;
mod convert;
pub mod event;
pub mod fs;
pub mod handlers;
pub mod http;
pub mod input;
pub mod job;
pub mod json;
pub mod keymap;
pub mod modal;
pub mod pick;
pub mod provider;
pub mod request;

pub mod registry;
pub mod schedule;
pub mod session;

pub mod status;
pub mod tools;
pub mod window;
pub mod wire;

use std::cell::{Cell, RefCell};
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::rc::Rc;

use mlua::{Function, Lua, Table, Value};

use self::action::Actions;
use uji_core::session::conversation::Shared;
use uji_ui::state::UiState;

use self::callbacks::Callbacks;
use self::handlers::Handlers;
use self::http::Fetches;
use self::input::Composer;
use self::job::Jobs;
use self::registry::Registry;
use self::tools::Tool;
use uji_core::llm::{Catalog, Retention};
use uji_ui::keymap::Keymap;

pub struct Api {
    state: Rc<RefCell<UiState>>,
    scheduled: RefCell<Vec<Function>>,
    handlers: RefCell<Handlers>,
    commands: RefCell<HashMap<String, command::LuaCommand>>,
    tools: RefCell<BTreeMap<String, Rc<Tool>>>,
    providers: RefCell<Catalog>,
    keymap: RefCell<Keymap>,
    packs: RefCell<Vec<PathBuf>>,
    notices: RefCell<Vec<String>>,
    jobs: RefCell<Jobs>,
    callbacks: RefCell<Callbacks>,
    fetches: RefCell<Fetches>,
    wires: RefCell<BTreeMap<String, Function>>,
    composer: RefCell<Composer>,
    capture: RefCell<Option<Function>>,
    conversation: Shared,
    requests: RefCell<Vec<request::Request>>,
    pick: RefCell<pick::Pick>,
    access: RefCell<tools::Access>,
    segments: RefCell<Registry>,
    context: RefCell<Registry>,
    compaction: RefCell<context::Compaction>,
    cache: Cell<Retention>,
    rules: RefCell<tools::Rules>,
    next_handler: Cell<u64>,
    actions: RefCell<Actions>,
}

impl Api {
    pub fn new(state: Rc<RefCell<UiState>>, conversation: Shared) -> Rc<Self> {
        Rc::new(Self {
            state,
            scheduled: RefCell::default(),
            handlers: RefCell::default(),
            commands: RefCell::default(),
            access: RefCell::default(),
            tools: RefCell::default(),
            providers: RefCell::default(),
            keymap: RefCell::default(),
            packs: RefCell::default(),
            notices: RefCell::default(),
            jobs: RefCell::default(),
            callbacks: RefCell::default(),
            fetches: RefCell::default(),
            wires: RefCell::default(),
            composer: RefCell::default(),
            capture: RefCell::default(),
            conversation,
            requests: RefCell::default(),
            pick: RefCell::default(),
            segments: RefCell::default(),
            context: RefCell::default(),
            compaction: RefCell::default(),
            cache: Cell::default(),
            rules: RefCell::default(),
            next_handler: Cell::new(0),
            actions: RefCell::default(),
        })
    }

    pub fn state(&self) -> &Rc<RefCell<UiState>> {
        &self.state
    }

    pub fn scheduled(&self) -> &RefCell<Vec<Function>> {
        &self.scheduled
    }

    pub fn commands(&self) -> &RefCell<HashMap<String, command::LuaCommand>> {
        &self.commands
    }

    pub fn tools(&self) -> &RefCell<BTreeMap<String, Rc<Tool>>> {
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

    pub fn capture(&self) -> &RefCell<Option<Function>> {
        &self.capture
    }

    pub fn composer(&self) -> &RefCell<Composer> {
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

    pub fn segments(&self) -> &RefCell<Registry> {
        &self.segments
    }

    pub fn actions(&self) -> &RefCell<Actions> {
        &self.actions
    }

    pub fn context(&self) -> &RefCell<Registry> {
        &self.context
    }

    pub fn compaction(&self) -> &RefCell<context::Compaction> {
        &self.compaction
    }

    pub fn cache(&self) -> &Cell<Retention> {
        &self.cache
    }

    pub fn rules(&self) -> &RefCell<tools::Rules> {
        &self.rules
    }

    pub fn next_handler_name(&self) -> String {
        let next = self.next_handler.get().saturating_add(1);
        self.next_handler.set(next);
        format!("handler {next}")
    }

    pub fn conversation(&self) -> &Shared {
        &self.conversation
    }

    pub fn jobs(&self) -> &RefCell<Jobs> {
        &self.jobs
    }

    pub fn callbacks(&self) -> &RefCell<Callbacks> {
        &self.callbacks
    }

    pub fn fetches(&self) -> &RefCell<Fetches> {
        &self.fetches
    }

    pub fn wires(&self) -> &RefCell<BTreeMap<String, Function>> {
        &self.wires
    }

    pub fn take_notices(&self) -> Vec<String> {
        std::mem::take(&mut *self.notices.borrow_mut())
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

    pub fn fold(&self, event: &str, payload: &Table, field: &str) {
        let _ = payload.set("event", event);
        let handlers = self.handlers.borrow().get(event);
        for handler in handlers {
            match handler.call::<Value>(payload.clone()) {
                Ok(Value::Nil) => {}
                Ok(value) => {
                    let _ = payload.set(field, value);
                }
                Err(err) => self.notify(format!("{event} handler error: {err}")),
            }
        }
    }

    pub fn ask(&self, event: &str, payload: &Table) -> Option<Value> {
        self.run(event, payload, Policy::FirstAnswer)
    }

    fn run(&self, event: &str, payload: &Table, policy: Policy) -> Option<Value> {
        let _ = payload.set("event", event);
        let handlers = self.handlers.borrow().get(event);
        for handler in handlers {
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
    ui.set("prompt", modal::prompt(lua, api)?)?;
    uji.set("ui", ui)?;

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
    status.set("list", status::list(lua, api)?)?;
    status.set("render", status::render(lua, api)?)?;
    uji.set("status", status)?;

    uji.set("json", json::register(lua, api)?)?;
    uji.set("schedule", schedule::schedule(lua, api)?)?;
    uji.set("defer", schedule::defer(lua, api)?)?;
    uji.set("on", event::on(lua, api)?)?;
    uji.set("off", event::off(lua, api)?)?;
    uji.set("emit", event::emit(lua, api)?)?;
    uji.set("notify", event::notify(lua, api)?)?;

    let tool = lua.create_table()?;
    tool.set("add", tools::add(lua, api)?)?;
    tool.set("remove", tools::remove(lua, api)?)?;
    tool.set("list", tools::list(lua, api)?)?;
    tool.set("enable", tools::enable(lua, api)?)?;
    tool.set("disable", tools::disable(lua, api)?)?;
    tool.set("roots", tools::roots(lua, api)?)?;
    tool.set("confine", tools::confine(lua, api)?)?;
    tool.set("policy", tools::policy_rules(lua, api)?)?;
    uji.set("tool", tool)?;

    uji.set("command", command::register(lua, api)?)?;
    uji.set("context", context::register(lua, api)?)?;
    uji.set("action", action::register(lua, api)?)?;
    uji.set("keymap", keymap::register(lua, api)?)?;
    uji.set("provider", provider::register(lua, api)?)?;
    uji.set("wire", wire::register(lua, api)?)?;
    uji.set("job", job::register(lua, api)?)?;
    uji.set("http", http::register(lua, api)?)?;
    uji.set("fs", fs::register(lua, api)?)?;
    uji.set("input", input::register(lua, api)?)?;
    uji.set("session", session::register(lua, api)?)?;

    Ok(uji)
}
