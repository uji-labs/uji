use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::Arc;

use crate::api::Api;
use mlua::{FromLuaMulti, Function, Lua as LuaState, LuaSerdeExt, Value as LuaValue};
use uji_core::session::conversation::Shared;
use uji_ui::model::ActiveModel;
use uji_ui::state::UiState;

use super::events::{self, Event, Hook};
use super::policy;
use crate::pack;
use std::collections::BTreeSet;
use uji_core::config;
use uji_core::llm::{Catalog, Dispatch, Llm, Provider};
use uji_core::session::store::SessionStorage;

use uji_core::tools::policy::ToolPolicy;

use super::loader;

const DEFAULTS: &str = "uji.defaults";

const TOOLS: &str = "uji.tools";

const WIRES: &str = "uji.wires";

const PROVIDERS: &str = "uji.providers";

pub(crate) struct Inner {
    pub(crate) lua: LuaState,
    pub(crate) api: Rc<Api>,
    pub(crate) llm: Arc<Llm>,
    pub(crate) llm_model: String,
    pub(crate) llm_provider: String,
    pub(crate) llm_effort: uji_core::llm::Effort,
    pub(crate) llm_caches: bool,
    pub(crate) client: Arc<reqwest::Client>,
    pub(crate) policy: ToolPolicy,
    pub(crate) dispatch: Dispatch,
    pub(crate) config_dir: Option<PathBuf>,
}

impl Inner {
    pub(crate) fn boot(
        state: Rc<RefCell<UiState>>,
        conversation: Shared,
        client: Arc<reqwest::Client>,
        config_dir: Option<PathBuf>,
        dispatch: Dispatch,
    ) -> Self {
        let mut inner = Self {
            lua: LuaState::new(),
            api: Api::new(state, conversation),
            llm: Arc::new(Llm::NotConfigured),
            llm_model: String::new(),
            llm_provider: String::new(),
            llm_effort: uji_core::llm::Effort::default(),
            llm_caches: false,
            client,
            policy: ToolPolicy::default(),
            dispatch,
            config_dir: config_dir.clone(),
        };

        let dir = config_dir.or_else(config::config_dir);
        if let Some(dir) = dir {
            inner.api.packs().borrow_mut().push(dir);
        }

        match crate::api::register(&inner.lua, &inner.api) {
            Ok(uji) => {
                match pack::register(&inner.lua, &inner.api) {
                    Ok(table) => {
                        if let Err(err) = uji.set("pack", table) {
                            inner.notify(format!("cannot expose uji.pack: {err}"));
                        }
                    }
                    Err(err) => inner.notify(format!("cannot build uji.pack: {err}")),
                }
                if let Err(err) = inner.lua.globals().set("uji", uji) {
                    inner.notify(format!("cannot expose the uji table: {err}"));
                }
            }
            Err(err) => inner.notify(format!("cannot build the uji table: {err}")),
        }
        if let Err(err) = loader::install(&inner.lua, &inner.api) {
            inner.notify(format!("cannot install the module loader: {err}"));
        }

        inner
            .api
            .actions()
            .borrow_mut()
            .reserve(uji_ui::app::Action::names().map(ToString::to_string));
        inner.load(WIRES);
        inner.load_providers();
        inner.load(TOOLS);
        inner.run_init();
        inner.source_plugins();
        inner.compile_policy();
        inner
    }

    pub(crate) fn notify(&self, message: String) {
        self.api.notify(message);
    }

    pub(crate) fn take_notices(&self) -> Vec<String> {
        self.api.take_notices()
    }

    pub(crate) fn compile_policy(&mut self) {
        let known = self.tool_names();
        self.api.rules().borrow_mut().settle();
        let (policy, notices) = policy::compile(self.api.rules().borrow().entries(), &known);
        self.policy = policy;
        for notice in notices {
            self.notify(notice);
        }
    }

    fn tool_names(&self) -> BTreeSet<String> {
        self.api.tools().borrow().keys().cloned().collect()
    }

    pub(crate) fn state(&self) -> &Rc<RefCell<UiState>> {
        self.api.state()
    }

    pub(crate) fn emit<E: Event>(&self, event: &E) {
        match events::payload(&self.lua, event) {
            Ok(payload) => self.api.dispatch(E::NAME, &payload),
            Err(err) => self.notify(format!("{}: {err}", E::NAME)),
        }
    }

    pub(crate) fn ask<E: Event>(&self, event: &E) -> Option<LuaValue> {
        match events::payload(&self.lua, event) {
            Ok(payload) => self.api.ask(E::NAME, &payload),
            Err(err) => {
                self.notify(format!("{}: {err}", E::NAME));
                None
            }
        }
    }

    pub(crate) fn fold<H: Hook>(&self, hook: &H, value: String) -> String {
        events::fold(&self.lua, &self.api, hook, &value).unwrap_or_else(|err| {
            self.notify(format!("{} left no {}: {err}", H::NAME, H::FIELD));
            value
        })
    }

    fn run_init(&self) {
        let path = self
            .api
            .packs()
            .borrow()
            .first()
            .and_then(|dir| config::init_path(dir));
        match path {
            Some(path) => self.source(&path),
            None => self.load(DEFAULTS),
        }
    }

    pub(crate) fn require<T: FromLuaMulti>(&self, module: &str) -> mlua::Result<T> {
        self.lua.globals().get::<Function>("require")?.call(module)
    }

    fn load_providers(&self) {
        let builtin = self
            .require::<LuaValue>(PROVIDERS)
            .and_then(|value| self.lua.from_value::<Vec<Provider>>(value));
        match builtin {
            Ok(builtin) => *self.api.providers().borrow_mut() = Catalog::new(builtin),
            Err(err) => self.notify(format!("{PROVIDERS}: {err}")),
        }
    }

    fn load(&self, module: &str) {
        if let Err(err) = self.require::<()>(module) {
            self.notify(format!("{module}: {err}"));
        }
    }

    fn source_plugins(&self) {
        let roots = self.api.packs().borrow().clone();
        for root in roots {
            for path in plugin_files(&root.join(config::PLUGIN_DIR)) {
                self.source(&path);
            }
        }
    }

    fn source(&self, path: &Path) {
        let name = path.display().to_string();
        match std::fs::read_to_string(path) {
            Ok(source) => {
                if let Err(err) = self.lua.load(&source).set_name(&name).exec() {
                    self.notify(format!("{name}: {err}"));
                }
            }
            Err(err) => self.notify(format!("cannot read {name}: {err}")),
        }
    }

    pub(crate) fn resolve_llm(&mut self, storage: &mut dyn SessionStorage) {
        let selection = uji_core::llm::resolve_from_storage(
            storage,
            &self.api.providers().borrow(),
            &self.dispatch,
        );
        let context_window = self
            .api
            .providers()
            .borrow()
            .get(&selection.id)
            .and_then(|provider| provider.budget(&selection.model))
            .map(|budget| budget.window);
        self.llm = selection.llm;
        self.llm_model.clone_from(&selection.model);
        self.llm_provider = selection.id;
        self.llm_effort = selection.effort;
        self.llm_caches = selection.caches;
        self.state().borrow_mut().set_active(ActiveModel {
            provider: Some(selection.name),
            model: Some(selection.model),
            effort: selection
                .effort
                .enabled()
                .then(|| selection.effort.to_string()),
            context_window,
        });
        self.emit(&events::ModelChanged {
            provider: &self.llm_provider,
            model: &self.llm_model,
        });
    }
}

fn plugin_files(dir: &Path) -> Vec<PathBuf> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut paths: Vec<PathBuf> = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "lua"))
        .collect();
    paths.sort();
    paths
}
