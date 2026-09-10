use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;

use mlua::Lua as LuaState;
use uji_api::Api;
use uji_api::state::UiState;

use crate::config::{self, DEFAULT_LUA};
use crate::llm::{Llm, NotConfigured};
use crate::session::store::SessionStorage;
use crate::tools::policy::ToolPolicy;
use crate::tools::policy_lua;

pub(crate) struct Inner {
    pub(crate) lua: LuaState,
    pub(crate) api: Rc<Api>,
    pub(crate) llm: RefCell<Arc<dyn Llm>>,
    pub(crate) llm_model: RefCell<String>,
    pub(crate) client: Arc<reqwest::Client>,
    pub(crate) policy: RefCell<ToolPolicy>,
}

impl Inner {
    pub(crate) fn new(lua: LuaState, api: Rc<Api>) -> Rc<Self> {
        Rc::new(Self {
            lua,
            api,
            llm: RefCell::new(Arc::new(NotConfigured)),
            llm_model: RefCell::default(),
            client: Arc::new(reqwest::Client::new()),
            policy: RefCell::new(ToolPolicy::default()),
        })
    }

    pub(crate) fn compile_policy(&self) {
        *self.policy.borrow_mut() = policy_lua::compile(&self.lua);
    }

    pub(crate) fn state(&self) -> Rc<RefCell<UiState>> {
        self.api.state()
    }

    pub(crate) fn emit(&self, event: &str, fields: &[(&str, String)]) {
        let Ok(ctx) = self.lua.create_table() else {
            return;
        };
        for (key, value) in fields {
            let _ = ctx.set(*key, value.clone());
        }
        self.api.dispatch(event, &ctx);
    }

    pub(crate) fn reload(&self) {
        self.state().borrow_mut().clear();
        self.run_init(None);
        self.load_plugins(None);
        self.compile_policy();
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

    pub(crate) fn resolve_llm(&self, storage: &mut dyn SessionStorage) {
        let (resolved, model, provider_id) = crate::llm::resolve_from_storage(storage);
        let name = crate::llm::provider(&provider_id)
            .map_or_else(|| provider_id.clone(), |p| p.name.clone());
        *self.llm.borrow_mut() = resolved;
        (*self.llm_model.borrow_mut()).clone_from(&model);
        self.state().borrow_mut().set_current_provider(name);
        self.state().borrow_mut().set_current_model(model);
    }
}
