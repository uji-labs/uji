use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;
use std::time::{Duration, Instant};

use crate::api::modal::{Answer, ModalKind, ModalRequest};
use mlua::Value as LuaValue;
use uji_agent::llm::{CancelToken, StreamEvent};
use uji_ui::model::RunState;

use uji_ui::app::Echo;

use super::{Control, LoopData, ModalInput};
use crate::api::request::Request;
use crate::cmd::LuaAction;
use crate::runtime::events;
use crate::runtime::job::JobEvent;
use crate::runtime::signal::Signal;
use crate::runtime::{Inner, job};

const FRAME: Duration = Duration::from_millis(16);

impl LoopData {
    pub(crate) fn bootstrap(&mut self) -> std::io::Result<()> {
        self.frontend.draw(&self.app)?;
        self.inner.resolve_llm(&mut *self.storage);
        self.discover_model_windows();
        self.inner.emit(events::Event::StatusChanged.name(), &[]);
        self.refresh_suggestions();
        self.frontend.draw(&self.app)?;
        self.dirty = false;
        Ok(())
    }

    pub(crate) fn pump(
        &mut self,
        handle: &calloop::LoopHandle<'static, Self>,
    ) -> std::io::Result<()> {
        self.apply_composer();
        self.drain_requests();
        self.sync_picker();
        self.drain_diagnostics();

        for callback in self.inner.api.scheduled().take() {
            let _ = handle.insert_idle(move |data: &mut LoopData| {
                if let Err(err) = callback.call::<()>(()) {
                    data.inner
                        .report(format!("scheduled callback error: {err}"));
                }
                data.dirty = true;
            });
        }

        if self.control == Control::Reload {
            self.perform_reload();
        }

        if self.last_reveal.elapsed() >= FRAME && self.app.reveal_step() {
            self.dirty = true;
            self.last_reveal = Instant::now();
        }
        self.release_deferred();

        if self.dirty {
            self.frontend.draw(&self.app)?;
            self.dirty = false;
        }
        Ok(())
    }

    pub(crate) fn frame_timeout(&self) -> Option<Duration> {
        (self.app.revealing() || !self.deferred.is_empty()).then_some(FRAME)
    }

    pub(super) fn release_deferred(&mut self) {
        while let Some(next) = self.deferred.front() {
            if self.app.revealing() && !matches!(next, StreamEvent::Delta(_)) {
                return;
            }
            let Some(event) = self.deferred.pop_front() else {
                return;
            };
            self.apply_llm_event(event);
        }
    }

    pub(crate) fn on_timer(&mut self) {
        if self.inner.state().borrow().run_state() == RunState::Working {
            self.inner.emit(events::Event::Tick.name(), &[]);
            self.dirty = true;
        }
    }

    pub(crate) fn timer_interval(&self) -> Duration {
        let ms = self.inner.state().borrow().opts().loader_interval_ms.max(1);
        Duration::from_millis(ms)
    }

    pub(crate) fn on_job_event(&mut self, event: &JobEvent) {
        let exited = matches!(event, JobEvent::Exit { .. });
        let id = event.id();
        let arg = match event {
            JobEvent::Stdout { line, .. } | JobEvent::Stderr { line, .. } => self.lua_text(line),
            JobEvent::Exit { code, .. } => LuaValue::Integer(i64::from(*code)),
        };
        let callback = {
            let jobs = self.inner.api.jobs();
            let jobs = jobs.borrow();
            jobs.handlers(id).and_then(|handlers| match event {
                JobEvent::Stdout { .. } => handlers.on_stdout.clone(),
                JobEvent::Stderr { .. } => handlers.on_stderr.clone(),
                JobEvent::Exit { .. } => handlers.on_exit.clone(),
            })
        };
        if let Some(callback) = callback
            && let Err(err) = callback.call::<()>((arg,))
        {
            self.inner.report(format!("job {id}: {err}"));
        }
        if exited {
            self.inner.api.jobs().borrow_mut().finish(id);
        }
        self.dirty = true;
    }

    pub(super) fn drain_diagnostics(&mut self) {
        let notices = self.inner.take_diagnostics();
        if !notices.is_empty() {
            self.app.overlay_mut().push_notices(notices);
            self.dirty = true;
        }
    }

    /// Carry out what plugins asked for, in the order they asked.
    fn drain_requests(&mut self) {
        for request in self.inner.api.take_requests() {
            match request {
                Request::Submit(text) => self.submit(&text),
                Request::SetTitle(title) => self.set_title(title),
                Request::Interrupt => {
                    self.interrupt();
                }
                Request::Answer(answer) => {
                    let input = match answer {
                        Answer::Select(Some(item)) => ModalInput::Select(item),
                        Answer::Prompt(Some(value)) => ModalInput::Prompt(value),
                        Answer::Select(None) | Answer::Prompt(None) => ModalInput::Cancel,
                    };
                    self.on_modal_answer(input);
                }
                Request::Modal(request) => self.open_modal(*request),
                Request::Exec(command) => self.exec(&command),
                Request::ToolResult(text) => self.finish_lua_tool(text),
                Request::JobStart { id, command, cwd } => self.start_job(id, command, cwd),
                Request::JobStop(id) => self.inner.api.jobs().borrow().stop(id),
                Request::JobWrite { id, data } => self.inner.api.jobs().borrow().write(id, data),
                Request::PickItems { items, token } => {
                    // Drop results whose query has already been superseded.
                    if token == self.inner.api.pick().borrow().token() {
                        self.app.set_pick_items(items);
                        self.dirty = true;
                    }
                }
            }
        }
    }

    fn exec(&mut self, command: &[String]) {
        let Some((program, args)) = command.split_first() else {
            return;
        };
        if let Err(err) = self.frontend.suspend() {
            self.inner.report(format!("suspend terminal: {err}"));
        }
        let status = std::process::Command::new(program).args(args).status();
        if let Err(err) = self.frontend.resume() {
            self.inner.report(format!("resume terminal: {err}"));
        }
        match status {
            Ok(status) if !status.success() => {
                self.inner.report(format!("{program} exited with {status}"));
            }
            Err(err) => self.inner.report(format!("run {program}: {err}")),
            Ok(_) => {}
        }
        self.dirty = true;
    }

    fn open_modal(&mut self, request: ModalRequest) {
        self.modal = Some(LuaAction::new(request.on_done));
        match request.kind {
            ModalKind::Select { items } => self.app.open_select(request.title, items),
            ModalKind::Pick { items, live } => self.app.open_pick(request.title, items, live),
            ModalKind::Prompt { value, hidden } => {
                let echo = if hidden { Echo::Hidden } else { Echo::Plain };
                self.app.open_prompt(request.title, value, echo);
            }
        }
        self.dirty = true;
    }

    fn apply_composer(&mut self) {
        let composer = self.inner.api.composer();
        if let Some(text) = composer.take_written() {
            self.app.set_input(text);
            self.dirty = true;
        } else {
            composer.observe(self.app.input());
        }
    }

    fn start_job(&mut self, id: u64, command: Vec<String>, cwd: Option<PathBuf>) {
        let cancel = CancelToken::new();
        let (stdin, writes) = tokio::sync::mpsc::unbounded_channel();
        self.inner
            .api
            .jobs()
            .borrow_mut()
            .attach(id, cancel.clone(), stdin);
        let sender = self.signals.clone();
        self.runtime
            .spawn(job::run(id, command, cwd, cancel, writes, move |event| {
                let _ = sender.send(Signal::Job(event));
            }));
    }

    fn perform_reload(&mut self) {
        self.control = Control::Run;
        let state = self.inner.state();
        state.borrow_mut().clear();
        let client = Arc::clone(&self.inner.client);
        let conversation = Rc::clone(self.app.conversation());
        self.inner = Inner::boot(state, conversation, client, self.config_dir.clone());
        self.inner.resolve_llm(&mut *self.storage);
        self.discover_model_windows();
        self.refresh_suggestions();
        self.drain_diagnostics();
        self.inner.emit(events::Event::StatusChanged.name(), &[]);
        self.dirty = true;
    }

    fn lua_text(&self, text: &str) -> LuaValue {
        self.inner
            .lua
            .create_string(text)
            .map_or(LuaValue::Nil, LuaValue::String)
    }
}
