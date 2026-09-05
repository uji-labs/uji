use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;

use mlua::{Lua as LuaState, Table};
use tui::state::UiState;
use uji_core::llm::{Echo, Llm, LlmConfig};

use super::handlers::Handlers;
use super::scheduled::Scheduled;
use crate::config::{self, DEFAULT_LUA};

pub(crate) struct Inner {
    pub(crate) lua: LuaState,
    pub(crate) state: Rc<RefCell<UiState>>,
    pub(crate) handlers: RefCell<Handlers>,
    pub(crate) scheduled: Scheduled,
    pub(crate) llm: RefCell<Arc<dyn Llm>>,
    pub(crate) llm_model: RefCell<String>,
}

impl Inner {
    pub(crate) fn new(lua: LuaState) -> Rc<Self> {
        Rc::new(Self {
            lua,
            state: Rc::new(RefCell::new(UiState::new())),
            handlers: RefCell::default(),
            scheduled: Scheduled::default(),
            llm: RefCell::new(Arc::new(Echo)),
            llm_model: RefCell::default(),
        })
    }

    pub(crate) fn emit(&self, event: &str, fields: &[(&str, String)]) {
        let Ok(ctx) = self.lua.create_table() else {
            return;
        };
        for (key, value) in fields {
            let _ = ctx.set(*key, value.clone());
        }
        self.dispatch(event, &ctx);
    }

    pub(crate) fn dispatch(&self, event: &str, ctx: &Table) {
        for handler in self.handlers.borrow().get(event) {
            if let Err(err) = handler.call::<()>((event, ctx.clone())) {
                eprintln!("uji: handler error for {event}: {err}");
            }
        }
    }

    pub(crate) fn reload(&self) {
        self.state.borrow_mut().clear();
        self.run_init(None);
        self.load_plugins(None);
        self.ensure_default_layout();
        self.sync_opts();
        self.sync_llm();
    }

    pub(crate) fn run_init(&self, config_path: Option<PathBuf>) {
        let path = config_path.or_else(config::config_path);
        let (source, name) = match path {
            Some(path) => match std::fs::read_to_string(&path) {
                Ok(source) => (source, path.display().to_string()),
                Err(err) => {
                    eprintln!("uji: cannot read config {}: {err}", path.display());
                    return;
                }
            },
            None => (DEFAULT_LUA.to_owned(), "default.lua".to_owned()),
        };
        if let Err(err) = self.lua.load(&source).set_name(&name).exec() {
            eprintln!("uji: config error in {name}: {err}");
        }
    }

    pub(crate) fn load_plugins(&self, plugin_dir: Option<PathBuf>) {
        let Some(dir) = plugin_dir.or_else(config::plugin_dir) else {
            return;
        };
        let Ok(entries) = std::fs::read_dir(&dir) else {
            return;
        };
        let mut paths: Vec<PathBuf> = entries
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| path.extension().is_some_and(|ext| ext == "lua"))
            .collect();
        paths.sort();
        for path in paths {
            let Ok(source) = std::fs::read_to_string(&path) else {
                continue;
            };
            let name = path.display().to_string();
            if let Err(err) = self.lua.load(&source).set_name(&name).exec() {
                eprintln!("uji: plugin error in {name}: {err}");
            }
        }
    }

    pub(crate) fn ensure_default_layout(&self) {
        if self.state.borrow().windows().is_empty() {
            let _ = self.lua.load(DEFAULT_LUA).set_name("default.lua").exec();
        }
    }

    pub(crate) fn sync_opts(&self) {
        let cursor_blink = self
            .lua
            .globals()
            .get::<Table>("uji")
            .and_then(|uji| uji.get::<Table>("opt"))
            .ok()
            .and_then(|opt| opt.get::<Option<bool>>("cursor_blink").ok().flatten())
            .unwrap_or(true);
        self.state.borrow_mut().set_cursor_blink(cursor_blink);
    }

    pub(crate) fn sync_llm(&self) {
        let mut config = LlmConfig::default();
        let table = self
            .lua
            .globals()
            .get::<Table>("uji")
            .ok()
            .and_then(|uji| uji.get::<Table>("opt").ok())
            .and_then(|opt| opt.get::<Table>("llm").ok());
        if let Some(table) = table {
            if let Some(provider) = table.get::<Option<String>>("provider").ok().flatten() {
                config.provider = provider;
            }
            if let Some(model) = table.get::<Option<String>>("model").ok().flatten() {
                config.model = model;
            }
            config.base_url = table.get::<Option<String>>("base_url").ok().flatten();
            config.api_key = table.get::<Option<String>>("api_key").ok().flatten();
        }
        if let Some(provider) = std::env::var("UJI_LLM_PROVIDER")
            .ok()
            .filter(|value| !value.is_empty())
        {
            config.provider = provider;
        }
        if let Some(model) = std::env::var("UJI_LLM_MODEL")
            .ok()
            .filter(|value| !value.is_empty())
        {
            config.model = model;
        }
        *self.llm.borrow_mut() = uji_core::llm::resolve(&config);
        *self.llm_model.borrow_mut() = config.model;
    }
}
