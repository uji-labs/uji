use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;

use mlua::{Lua as LuaState, Table};
use uji_api::Api;
use uji_api::model::{Border, LoaderMode, Size, Split, WaitingOpts, WinOpts, WindowKind};
use uji_api::state::UiState;

use crate::config::{self, DEFAULT_LUA};
use crate::llm::{Llm, NotConfigured};
use crate::session::store::SessionStorage;

pub(crate) struct Inner {
    pub(crate) lua: LuaState,
    pub(crate) api: Rc<Api>,
    pub(crate) llm: RefCell<Arc<dyn Llm>>,
    pub(crate) llm_model: RefCell<String>,
    pub(crate) client: Arc<reqwest::Client>,
}

impl Inner {
    pub(crate) fn new(lua: LuaState, api: Rc<Api>) -> Rc<Self> {
        Rc::new(Self {
            lua,
            api,
            llm: RefCell::new(Arc::new(NotConfigured)),
            llm_model: RefCell::default(),
            client: Arc::new(reqwest::Client::new()),
        })
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
        self.apply_ui_config();
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

    pub(crate) fn apply_ui_config(&self) {
        let ui = self
            .lua
            .globals()
            .get::<Table>("uji")
            .ok()
            .and_then(|uji| uji.get::<Table>("ui").ok());

        let messages_border = ui
            .as_ref()
            .and_then(|ui| ui.get::<Table>("messages").ok())
            .and_then(|m| m.get::<Option<String>>("border").ok().flatten())
            .and_then(|b| b.parse::<Border>().ok())
            .unwrap_or(Border::None);

        let input = ui.as_ref().and_then(|ui| ui.get::<Table>("input").ok());
        let input_height = input
            .as_ref()
            .and_then(|i| i.get::<Option<i64>>("height").ok().flatten())
            .and_then(|n| u16::try_from(n).ok())
            .unwrap_or(3);
        let cursor_blink = input
            .as_ref()
            .and_then(|i| i.get::<Option<bool>>("cursor_blink").ok().flatten())
            .unwrap_or(true);

        let footer_hint = ui
            .as_ref()
            .and_then(|ui| ui.get::<Table>("footer").ok())
            .and_then(|f| f.get::<Option<String>>("hint").ok().flatten())
            .unwrap_or_else(|| "ctrl+c exit".into());

        let suggest = ui.as_ref().and_then(|ui| ui.get::<Table>("suggest").ok());
        let suggest_enabled = suggest
            .as_ref()
            .and_then(|s| s.get::<Option<bool>>("enabled").ok().flatten())
            .unwrap_or(true);
        let suggest_max_height = suggest
            .as_ref()
            .and_then(|s| s.get::<Option<i64>>("max_height").ok().flatten())
            .and_then(|n| u16::try_from(n).ok())
            .unwrap_or(5);

        let waiting = ui.as_ref().and_then(|ui| ui.get::<Table>("waiting").ok());
        let waiting_text = waiting
            .as_ref()
            .and_then(|w| w.get::<Option<String>>("text").ok().flatten())
            .unwrap_or_else(|| "Working".into());
        let loader = waiting.as_ref().and_then(|w| w.get::<Table>("loader").ok());
        let loader_mode = loader
            .as_ref()
            .and_then(|l| l.get::<Option<String>>("mode").ok().flatten())
            .and_then(|m| m.parse::<LoaderMode>().ok())
            .unwrap_or(LoaderMode::Braille);
        let loader_interval_ms = loader
            .as_ref()
            .and_then(|l| l.get::<Option<i64>>("interval_ms").ok().flatten())
            .and_then(|n| u64::try_from(n).ok())
            .unwrap_or(80);

        let state_rc = self.state();
        let mut state = state_rc.borrow_mut();
        let _ = uji_api::window::open(
            &mut state,
            WindowKind::Messages,
            Vec::new(),
            WinOpts {
                split: Split::Top,
                size: Size::Fill,
                border: messages_border,
                title: None,
            },
        );
        let _ = uji_api::window::open(
            &mut state,
            WindowKind::Status,
            Vec::new(),
            WinOpts {
                split: Split::Bottom,
                size: Size::Fixed(1),
                border: Border::None,
                title: None,
            },
        );
        let _ = uji_api::window::open(
            &mut state,
            WindowKind::Input,
            Vec::new(),
            WinOpts {
                split: Split::Bottom,
                size: Size::Fixed(input_height),
                border: Border::None,
                title: None,
            },
        );
        state.set_cursor_blink(cursor_blink);
        state.set_footer_hint(footer_hint);
        state.set_suggest_enabled(suggest_enabled);
        state.set_suggest_max_height(suggest_max_height);
        state.set_waiting(WaitingOpts {
            text: waiting_text,
            loader_mode,
            loader_interval_ms,
        });
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
