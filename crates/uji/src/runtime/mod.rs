mod builtin;
mod error;
pub mod events;
mod inner;
mod input;
mod loop_data;

pub use error::RuntimeError;
pub(crate) use inner::Inner;
pub(crate) use loop_data::LoopData;

use std::cell::RefCell;
use std::io;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use calloop::{EventLoop, LoopHandle};
use crossterm::event::Event as TermEvent;
use mlua::Lua as LuaState;
use uji_api::Api;
use uji_api::state::UiState;

use crate::app::{self, App};
use crate::llm::StreamEvent;
use crate::session::model::Session;
use crate::session::store::SessionStorage;

pub struct Runtime {
    inner: Rc<Inner>,
    loop_handle: LoopHandle<'static, LoopData>,
    event_loop: EventLoop<'static, LoopData>,
}

impl Runtime {
    pub fn boot() -> Result<Self, RuntimeError> {
        Self::boot_in(None, None)
    }

    pub fn boot_in(
        config_path: Option<PathBuf>,
        plugin_dir: Option<PathBuf>,
    ) -> Result<Self, RuntimeError> {
        let inner = Inner::new(
            LuaState::new(),
            Api::new(Rc::new(RefCell::new(UiState::new()))),
        );
        let uji = uji_api::register(&inner.lua, &inner.api)?;
        let _ = inner.lua.globals().set("uji", uji);

        let event_loop = EventLoop::try_new()?;
        let loop_handle = event_loop.handle();

        inner.run_init(config_path);
        inner.load_plugins(plugin_dir);
        inner.compile_policy();

        Ok(Self {
            inner,
            loop_handle,
            event_loop,
        })
    }

    pub fn emit(&self, event: &str, fields: &[(&str, String)]) {
        self.inner.emit(event, fields);
    }

    pub fn state(&self) -> Rc<RefCell<UiState>> {
        self.inner.state()
    }

    pub fn eval(&self, chunk: &str) -> mlua::Result<()> {
        self.inner.lua.load(chunk).exec()
    }

    pub fn run(self, session: Session, mut storage: Box<dyn SessionStorage>) -> io::Result<()> {
        let Self {
            inner,
            loop_handle,
            mut event_loop,
        } = self;

        let messages = storage.messages(&session.id).map_err(io::Error::other)?;
        let app = App::new(session, messages, inner.state());

        let terminal = app::setup()?;
        let (sender, channel) = calloop::channel::channel::<TermEvent>();
        let reader_running = Arc::new(AtomicBool::new(true));
        input::spawn(sender, reader_running.clone());

        let (llm_sender, llm_channel) = calloop::channel::channel::<StreamEvent>();

        let runtime = tokio::runtime::Runtime::new()?;
        let mut data = LoopData {
            inner,
            app,
            storage,
            terminal,
            dirty: false,
            running: true,
            llm_tx: llm_sender,
            active: None,
            action_done: false,
            pending_tool: None,
            runtime,
        };

        data.inner.resolve_llm(&mut *data.storage);
        data.inner.emit("status_changed", &[]);
        data.refresh_suggestions();

        event_loop
            .handle()
            .insert_source(channel, |event, _meta, data: &mut LoopData| match event {
                calloop::channel::Event::Msg(event) => data.on_term_event(&event),
                calloop::channel::Event::Closed => data.running = false,
            })
            .map_err(|err| io::Error::other(format!("register input source: {err}")))?;

        event_loop
            .handle()
            .insert_source(llm_channel, |event, _meta, data: &mut LoopData| {
                if let calloop::channel::Event::Msg(event) = event {
                    data.on_llm_event(event);
                }
            })
            .map_err(|err| io::Error::other(format!("register llm source: {err}")))?;

        let timer = calloop::timer::Timer::from_duration(data.timer_interval());
        event_loop
            .handle()
            .insert_source(timer, |_event, _meta, data: &mut LoopData| {
                data.on_timer();
                calloop::timer::TimeoutAction::ToDuration(data.timer_interval())
            })
            .map_err(|err| io::Error::other(format!("register timer source: {err}")))?;

        app::draw(&mut data.terminal, &data.app)?;
        data.dirty = false;

        while data.running {
            event_loop
                .dispatch(None, &mut data)
                .map_err(io::Error::other)?;

            for callback in data.inner.api.scheduled().take() {
                let _ = loop_handle.insert_idle(move |data: &mut LoopData| {
                    if let Err(err) = callback.call::<()>(()) {
                        eprintln!("uji: scheduled callback error: {err}");
                    }
                    data.dirty = true;
                });
            }

            if data.dirty {
                app::draw(&mut data.terminal, &data.app)?;
                data.dirty = false;
            }
        }

        reader_running.store(false, Ordering::Relaxed);
        data.inner.emit(events::QUIT, &[]);
        app::restore(&mut data.terminal)
    }
}
