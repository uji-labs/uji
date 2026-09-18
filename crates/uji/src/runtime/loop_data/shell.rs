//! Running a command typed as `!ls` in the composer.
//!
//! The command is the user's, not the model's: it skips the tool policy, and
//! what it prints is shown in the transcript and kept with the session but never
//! sent to the model. Output streams into the activity line while it runs, and
//! lands as one message when it exits.

use std::path::PathBuf;

use uji_agent::llm::CancelToken;
use uji_agent::session::model::Message;

use super::LoopData;
use crate::runtime::events;
use crate::runtime::job::{self, JobEvent};
use crate::runtime::signal::Signal;

/// Jobs the user starts from Lua are numbered from zero, so the shell takes the
/// far end of the range and can never collide with one.
const SHELL_JOB: u64 = u64::MAX;
const MAX_LINES: usize = 500;
const MAX_BYTES: usize = 64 * 1024;
const FALLBACK_SHELL: &str = "/bin/sh";

pub(crate) struct Running {
    command: String,
    output: Vec<String>,
    bytes: usize,
    truncated: bool,
    cancelled: bool,
    cancel: CancelToken,
}

impl Running {
    fn new(command: String, cancel: CancelToken) -> Self {
        Self {
            command,
            output: Vec::new(),
            bytes: 0,
            truncated: false,
            cancelled: false,
            cancel,
        }
    }

    /// Keep the output bounded: a runaway command must not be able to push the
    /// whole transcript out of memory.
    fn push(&mut self, line: &str) {
        if self.truncated {
            return;
        }
        if self.output.len() >= MAX_LINES || self.bytes.saturating_add(line.len()) > MAX_BYTES {
            self.truncated = true;
            return;
        }
        self.bytes = self.bytes.saturating_add(line.len()).saturating_add(1);
        self.output.push(line.to_string());
    }

    fn finish(mut self) -> (String, String) {
        if self.truncated {
            self.output.push(String::from("… output truncated"));
        }
        if self.cancelled {
            self.output.push(String::from("… interrupted"));
        }
        (self.command, self.output.join("\n"))
    }
}

impl LoopData {
    pub(crate) fn run_shell(&mut self, command: &str) {
        if self.shell.is_some() {
            self.app
                .overlay_mut()
                .push_notices(vec![String::from("a command is already running")]);
            self.dirty = true;
            return;
        }
        let cancel = CancelToken::new();
        let (stdin, writes) = tokio::sync::mpsc::unbounded_channel();
        // Nothing writes to the child, and dropping the sender closes its stdin
        // so a command that reads gets an EOF instead of hanging the UI.
        drop(stdin);
        let sender = self.signals.clone();
        let argv = vec![shell_program(), String::from("-c"), command.to_string()];
        let cwd = PathBuf::from(&self.app.session().directory);
        self.runtime.spawn(job::run(
            SHELL_JOB,
            argv,
            Some(cwd),
            cancel.clone(),
            writes,
            move |event| {
                let _ = sender.send(Signal::Shell(event));
            },
        ));
        self.shell = Some(Running::new(command.to_string(), cancel));
        // Whatever it prints is the point of running it, so follow the
        // transcript down to it.
        self.app.reset_scroll();
        self.app
            .overlay_mut()
            .set_running(Some((progress_name(command), String::new())));
        self.inner.emit(
            events::Event::ShellStarted.name(),
            &[("command", command.to_string())],
        );
        self.dirty = true;
    }

    pub(crate) fn on_shell_event(&mut self, event: &JobEvent) {
        match event {
            JobEvent::Stdout { line, .. } | JobEvent::Stderr { line, .. } => {
                let Some(running) = self.shell.as_mut() else {
                    return;
                };
                running.push(line);
                let progress = (progress_name(&running.command), line.clone());
                self.app.overlay_mut().set_running(Some(progress));
            }
            JobEvent::Exit { code, .. } => {
                let Some(running) = self.shell.take() else {
                    return;
                };
                let code = if running.cancelled { 130 } else { *code };
                let (command, output) = running.finish();
                // A tool may have claimed the activity line in the meantime;
                // only take it back if what it shows is still this command.
                let ours = self
                    .app
                    .overlay()
                    .running()
                    .is_some_and(|(name, _)| name == progress_name(&command));
                if ours {
                    self.app.overlay_mut().set_running(None);
                }
                self.inner.emit(
                    events::Event::ShellFinished.name(),
                    &[("command", command.clone()), ("code", code.to_string())],
                );
                self.append(Message::Shell {
                    command,
                    output,
                    code,
                });
            }
        }
        self.dirty = true;
    }

    /// Stop a running command. Interrupting reaches for this before the agent,
    /// because the command is what the user is watching.
    pub(crate) fn cancel_shell(&mut self) -> bool {
        let Some(running) = self.shell.as_mut() else {
            return false;
        };
        running.cancelled = true;
        running.cancel.cancel();
        self.dirty = true;
        true
    }
}

/// What the activity line calls a running command. It doubles as the marker
/// for whether that line still belongs to the shell.
fn progress_name(command: &str) -> String {
    format!("! {command}")
}

fn shell_program() -> String {
    std::env::var("SHELL")
        .ok()
        .filter(|shell| !shell.is_empty())
        .unwrap_or_else(|| String::from(FALLBACK_SHELL))
}
