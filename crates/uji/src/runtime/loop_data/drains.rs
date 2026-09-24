use std::path::PathBuf;
use std::rc::Rc;
use std::sync::Arc;
use std::time::Duration;

use crate::api::modal::{Answer, ModalKind, ModalRequest};
use uji_core::llm::CancelToken;
use uji_ui::model::RunState;

use uji_ui::app::Echo;

use super::reports::Reported;
use super::{Control, FRAME, LoopData, ModalInput};
use crate::api::request::Request;
use crate::cmd::LuaAction;
use crate::runtime::events;
use crate::runtime::job::JobEvent;
use crate::runtime::renderer::LuaRenderer;
use crate::runtime::signal::Signal;
use crate::runtime::{Inner, job};

impl LoopData {
    pub(crate) fn bootstrap(&mut self) -> std::io::Result<()> {
        self.answer_unanswered_calls();
        self.frontend.draw(&self.app)?;
        self.inner.resolve_llm(&mut *self.storage);
        self.discover_model_windows();
        self.inner.emit(&events::StatusChanged);
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
        if self.inner.api.rules().borrow().changed() {
            self.inner.compile_policy();
        }
        self.reap_calls();
        self.sync_picker();
        self.drain_notices();

        let scheduled = std::mem::take(&mut *self.inner.api.scheduled().borrow_mut());
        for callback in scheduled {
            let _ = handle.insert_idle(move |data: &mut LoopData| {
                if let Err(err) = callback.call::<()>(()) {
                    data.inner
                        .notify(format!("scheduled callback error: {err}"));
                }
                data.dirty = true;
            });
        }

        if self.control == Control::Reload {
            self.perform_reload();
        }

        if self.reveal.due() && self.app.reveal_step() {
            self.dirty = true;
            self.reveal.stepped();
        }
        self.release_deferred();

        if self.dirty {
            self.frontend.draw(&self.app)?;
            self.dirty = false;
        }
        Ok(())
    }

    pub(crate) fn frame_timeout(&self) -> Option<Duration> {
        (self.app.revealing() || self.reveal.holding()).then_some(FRAME)
    }

    pub(super) fn release_deferred(&mut self) {
        while let Some(reported) = self.reveal.release(self.app.revealing()) {
            self.apply_report(reported);
        }
    }

    pub(crate) fn on_timer(&mut self) {
        if self.inner.state().borrow().run_state() == RunState::Working {
            self.inner.emit(&events::LoaderTicked);
            self.dirty = true;
        }
    }

    pub(crate) fn timer_interval(&self) -> Duration {
        self.inner.state().borrow().loader_interval()
    }

    pub(crate) fn on_job_event(&mut self, event: &JobEvent) {
        let exited = matches!(event, JobEvent::Exit { .. });
        let id = event.id();
        let callback =
            self.inner
                .api
                .jobs()
                .borrow()
                .handlers(id)
                .and_then(|handlers| match event {
                    JobEvent::Stdout { .. } => handlers.stdout.clone(),
                    JobEvent::Stderr { .. } => handlers.stderr.clone(),
                    JobEvent::Exit { .. } => handlers.exit.clone(),
                });
        if let Some(callback) = callback
            && let Err(err) = event
                .args(&self.inner.lua)
                .and_then(|args| callback.call::<()>(args))
        {
            self.inner.notify(format!("job {id}: {err}"));
        }
        if exited {
            self.inner.api.jobs().borrow_mut().finish(id);
        }
        self.dirty = true;
    }

    pub(super) fn drain_notices(&mut self) {
        let notices = self.inner.take_notices();
        if !notices.is_empty() {
            self.app.overlay_mut().push_notices(notices);
            self.dirty = true;
        }
    }

    /// Carry out what plugins asked for, in the order they asked.
    fn drain_requests(&mut self) {
        loop {
            let requests = self.inner.api.take_requests();
            if requests.is_empty() {
                return;
            }
            for request in requests {
                self.carry_out(request);
            }
        }
    }

    fn carry_out(&mut self, request: Request) {
        match request {
            Request::Submit(text) => self.submit(&text),
            Request::SetTitle(title) => self.set_title(&title),
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
            Request::ToolResult { call, text } => self.finish_tool(call, text),
            Request::Report { event, on_applied } => {
                self.on_report(Reported { event, on_applied });
            }
            Request::Steer(id) => self.steer(id),
            Request::Approve {
                id,
                name,
                arguments,
            } => self.handle_tool_decision(id, &name, arguments),
            Request::RunTool {
                id,
                name,
                arguments,
            } => self.run_tool(id, name, arguments),
            Request::Stop(id) => self.stop_pending(id),
            Request::Compact { id, messages } => self.start_compact(id, messages),
            Request::Route(id) => self.start_route(id),
            Request::Defer { id, after } => self.start_defer(id, after),
            Request::ToolProgress { call, line } => self.tool_progress(call, line),
            Request::JobStart {
                id,
                command,
                cwd,
                timeout,
            } => self.start_job(id, command, cwd, timeout),
            Request::JobStop(id) => self.inner.api.jobs().borrow().stop(id),
            Request::JobWrite { id, data } => self.inner.api.jobs().borrow().write(id, data),
            Request::Fetch { id, fetch } => self.start_fetch(id, *fetch),
            Request::Fs { id, op } => self.start_fs(id, op),
            Request::PickItems { items, token } => {
                // Drop results whose query has already been superseded.
                if token == self.inner.api.pick().borrow().token() {
                    self.app.set_pick_items(items);
                    self.dirty = true;
                }
            }
        }
    }

    fn exec(&mut self, command: &[String]) {
        let Some((program, args)) = command.split_first() else {
            return;
        };
        if let Err(err) = self.frontend.suspend() {
            self.inner.notify(format!("suspend terminal: {err}"));
        }
        let status = std::process::Command::new(program).args(args).status();
        if let Err(err) = self.frontend.resume() {
            self.inner.notify(format!("resume terminal: {err}"));
        }
        match status {
            Ok(status) if !status.success() => {
                self.inner.notify(format!("{program} exited with {status}"));
            }
            Err(err) => self.inner.notify(format!("run {program}: {err}")),
            Ok(_) => {}
        }
        self.dirty = true;
    }

    fn open_modal(&mut self, request: ModalRequest) {
        self.command.modal = Some(LuaAction::new(request.on_done));
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
        let written = self.inner.api.composer().borrow_mut().take_written();
        match written {
            Some(text) => {
                self.app.set_input(text);
                self.dirty = true;
            }
            None => self
                .inner
                .api
                .composer()
                .borrow_mut()
                .observe(self.app.input()),
        }
    }

    fn start_job(
        &mut self,
        id: u64,
        command: Vec<String>,
        cwd: Option<PathBuf>,
        timeout: Option<Duration>,
    ) {
        let cancel = CancelToken::new();
        let (stdin, writes) = tokio::sync::mpsc::unbounded_channel();
        self.inner
            .api
            .jobs()
            .borrow_mut()
            .attach(id, cancel.clone(), stdin);
        self.work.stream(|signals| {
            job::run(id, command, cwd, timeout, cancel, writes, move |event| {
                let _ = signals.send(Signal::Job(event));
            })
        });
    }

    fn perform_reload(&mut self) {
        self.control = Control::Run;
        let state = Rc::clone(self.inner.state());
        state.borrow_mut().clear();
        let client = Arc::clone(&self.inner.client);
        let conversation = Rc::clone(self.app.conversation());
        let dispatch = Arc::clone(&self.inner.dispatch);
        self.inner = Inner::boot(
            state,
            conversation,
            client,
            self.inner.config_dir.clone(),
            dispatch,
        );
        self.app.set_renderer(Box::new(LuaRenderer::new(
            self.inner.lua.clone(),
            Rc::clone(&self.inner.api),
        )));
        self.inner.resolve_llm(&mut *self.storage);
        self.discover_model_windows();
        self.refresh_suggestions();
        self.drain_notices();
        self.inner.emit(&events::StatusChanged);
        self.dirty = true;
    }
}
