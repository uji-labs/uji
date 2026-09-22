//! Running a command typed as `!ls` in the composer.
//!
//! The command is the user's, not the model's: it skips the tool policy, and
//! what it prints is shown in the transcript and kept with the session but never
//! sent to the model. Output streams into the activity line while it runs, and
//! lands as one message when it exits.

use std::path::PathBuf;

use uji_agent::llm::CancelToken;
use uji_agent::process::{self, Capture, Exit, Spec};
use uji_agent::session::model::Message;

use super::LoopData;
use crate::runtime::events;
use crate::runtime::signal::Signal;

const MAX_OUTPUT: usize = 64 * 1024;
const FALLBACK_SHELL: &str = "/bin/sh";

pub(crate) enum ShellEvent {
    Line(String),
    Done(Exit),
}

pub(crate) struct Running {
    command: String,
    output: Capture,
    cancel: CancelToken,
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
        let sender = self.signals.clone();
        let argv = vec![shell_program(), String::from("-c"), command.to_string()];
        let cwd = PathBuf::from(&self.app.session().directory);
        let token = cancel.clone();
        self.runtime.spawn(async move {
            let spec = Spec::argv(&argv).in_dir(&cwd);
            let exit = process::stream(spec, &token, |_, line| {
                let _ = sender.send(Signal::Shell(ShellEvent::Line(line)));
            })
            .await;
            let exit = exit.unwrap_or(Exit::Code(-1));
            let _ = sender.send(Signal::Shell(ShellEvent::Done(exit)));
        });
        self.shell = Some(Running {
            command: command.to_string(),
            output: Capture::new(MAX_OUTPUT),
            cancel,
        });
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

    pub(crate) fn on_shell_event(&mut self, event: ShellEvent) {
        match event {
            ShellEvent::Line(line) => {
                let Some(running) = self.shell.as_mut() else {
                    return;
                };
                running.output.push(&line);
                let progress = (progress_name(&running.command), line);
                self.app.overlay_mut().set_running(Some(progress));
            }
            ShellEvent::Done(exit) => {
                let Some(running) = self.shell.take() else {
                    return;
                };
                let code = match exit {
                    Exit::Code(code) => code,
                    Exit::Cancelled => 130,
                    Exit::TimedOut => 124,
                };
                let command = running.command;
                let mut output = running.output.finish();
                if exit == Exit::Cancelled {
                    if !output.is_empty() {
                        output.push('\n');
                    }
                    output.push_str("… interrupted");
                }
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
        let Some(running) = self.shell.as_ref() else {
            return false;
        };
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
