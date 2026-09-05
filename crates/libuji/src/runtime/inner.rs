use std::cell::RefCell;
use std::collections::HashMap;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;

use mlua::{Function, Lua as LuaState, Table};
use tui::state::UiState;
use uji_core::credential;
use uji_core::llm::{Echo, Llm, LlmConfig};
use uji_core::session::store::SessionStorage;

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
    pub(crate) commands: RefCell<HashMap<String, Function>>,
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
            commands: RefCell::default(),
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
        let opt = self
            .lua
            .globals()
            .get::<Table>("uji")
            .ok()
            .and_then(|uji| uji.get::<Table>("ui").ok())
            .and_then(|ui| ui.get::<Table>("opt").ok());

        let cursor_blink = opt
            .as_ref()
            .and_then(|opt| opt.get::<Option<bool>>("cursor_blink").ok().flatten())
            .unwrap_or(true);
        self.state.borrow_mut().set_cursor_blink(cursor_blink);

        let suggest = opt
            .as_ref()
            .and_then(|opt| opt.get::<Table>("suggest").ok());
        let suggest_enabled = suggest
            .as_ref()
            .and_then(|suggest| suggest.get::<Option<bool>>("enabled").ok().flatten())
            .unwrap_or(true);
        let suggest_max_height = suggest
            .as_ref()
            .and_then(|suggest| suggest.get::<Option<i64>>("max_height").ok().flatten())
            .and_then(|n| u16::try_from(n).ok())
            .unwrap_or(5);
        self.state.borrow_mut().set_suggest_enabled(suggest_enabled);
        self.state
            .borrow_mut()
            .set_suggest_max_height(suggest_max_height);

        let footer_hint = opt
            .as_ref()
            .and_then(|opt| opt.get::<Table>("footer").ok())
            .and_then(|footer| footer.get::<Option<String>>("hint").ok().flatten())
            .unwrap_or_else(|| "ctrl+c exit".into());
        self.state.borrow_mut().set_footer_hint(footer_hint);
    }

    pub(crate) fn resolve_llm(&self, storage: &mut dyn SessionStorage) {
        let provider = storage
            .get_setting("llm.provider")
            .ok()
            .flatten()
            .unwrap_or_else(|| "echo".into());
        let model = storage
            .get_setting("llm.model")
            .ok()
            .flatten()
            .unwrap_or_default();
        let base_url = storage.get_setting("llm.base_url").ok().flatten();
        let api_key = credential::get(&provider);
        let config = LlmConfig {
            provider,
            model: model.clone(),
            base_url,
            api_key,
        };
        let resolved = uji_core::llm::resolve(&config);
        let id = resolved.id().to_string();
        *self.llm.borrow_mut() = resolved;
        (*self.llm_model.borrow_mut()).clone_from(&model);
        self.state.borrow_mut().set_current_provider(id);
        self.state.borrow_mut().set_current_model(model);
    }
}
