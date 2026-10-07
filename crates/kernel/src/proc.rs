use std::collections::HashMap;
use std::process::{ExitStatus, Stdio};

use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, Command};
use tokio::sync::{Mutex, mpsc, watch};
use uji_macros::{function, methods, options, value};

const NEWLINE: u8 = b'\n';
const RETURN: u8 = b'\r';

#[value]
#[derive(Clone, Copy)]
#[serde(rename_all = "lowercase")]
enum Stream {
    Stdout,
    Stderr,
}

struct Line {
    stream: Stream,
    text: String,
}

#[value]
#[derive(Clone, Copy)]
struct Exit {
    code: Option<i32>,
    signal: Option<i32>,
    success: bool,
}

impl Exit {
    const LOST: Self = Self {
        code: None,
        signal: None,
        success: false,
    };

    fn of(status: &std::io::Result<ExitStatus>) -> Self {
        let Ok(status) = status else {
            return Self::LOST;
        };
        Self {
            code: status.code(),
            signal: signal(*status),
            success: status.success(),
        }
    }
}

#[cfg(unix)]
fn signal(status: ExitStatus) -> Option<i32> {
    use std::os::unix::process::ExitStatusExt;
    status.signal()
}

#[cfg(not(unix))]
fn signal(_: ExitStatus) -> Option<i32> {
    None
}

pub(crate) struct Proc {
    pid: Option<u32>,
    group: Option<i32>,
    stdin: Mutex<Option<ChildStdin>>,
    output: Mutex<mpsc::UnboundedReceiver<Line>>,
    status: watch::Receiver<Option<Exit>>,
    kill: mpsc::UnboundedSender<()>,
}

impl Proc {
    fn start(mut child: Child, grouped: bool) -> Self {
        let (lines, output) = mpsc::unbounded_channel();
        if let Some(stdout) = child.stdout.take() {
            tokio::spawn(pipe(stdout, Stream::Stdout, lines.clone()));
        }
        if let Some(stderr) = child.stderr.take() {
            tokio::spawn(pipe(stderr, Stream::Stderr, lines));
        }
        let (report, status) = watch::channel(None);
        let (kill, killed) = mpsc::unbounded_channel();
        let pid = child.id();
        let group = pid
            .filter(|_| grouped)
            .and_then(|id| i32::try_from(id).ok());
        let stdin = child.stdin.take();
        tokio::spawn(supervise(child, group, killed, report));
        Self {
            pid,
            group,
            stdin: Mutex::new(stdin),
            output: Mutex::new(output),
            status,
            kill,
        }
    }
}

async fn pipe(reader: impl AsyncRead + Unpin, stream: Stream, lines: mpsc::UnboundedSender<Line>) {
    let mut reader = BufReader::new(reader);
    let mut buffer = Vec::new();
    loop {
        buffer.clear();
        match reader.read_until(NEWLINE, &mut buffer).await {
            Ok(0) | Err(_) => return,
            Ok(_) => {
                if buffer.last() == Some(&NEWLINE) {
                    buffer.pop();
                }
                if buffer.last() == Some(&RETURN) {
                    buffer.pop();
                }
                let text = String::from_utf8_lossy(&buffer).into_owned();
                if lines.send(Line { stream, text }).is_err() {
                    return;
                }
            }
        }
    }
}

impl Drop for Proc {
    fn drop(&mut self) {
        if self.status.borrow().is_none() {
            stop_group(self.group);
        }
    }
}

#[cfg(unix)]
#[allow(unsafe_code)]
fn own_session(command: &mut Command) {
    unsafe {
        command.pre_exec(|| {
            nix::unistd::setsid()
                .map(drop)
                .map_err(std::io::Error::from)
        });
    }
}

#[cfg(not(unix))]
fn own_session(_: &mut Command) {}

#[cfg(unix)]
fn stop_group(group: Option<i32>) -> bool {
    use nix::sys::signal::{Signal, killpg};
    use nix::unistd::Pid;
    group.is_some_and(|id| killpg(Pid::from_raw(id), Signal::SIGKILL).is_ok())
}

#[cfg(not(unix))]
fn stop_group(_: Option<i32>) -> bool {
    false
}

async fn supervise(
    mut child: Child,
    group: Option<i32>,
    mut killed: mpsc::UnboundedReceiver<()>,
    report: watch::Sender<Option<Exit>>,
) {
    let status = tokio::select! {
        status = child.wait() => status,
        _ = killed.recv() => {
            if !stop_group(group) {
                drop(child.start_kill());
            }
            child.wait().await
        }
    };
    report.send_replace(Some(Exit::of(&status)));
}

#[methods]
impl Proc {
    #[get]
    fn pid(&self) -> Option<u32> {
        self.pid
    }

    #[iterate(lines)]
    async fn line(&self) -> (Option<String>, Option<Stream>) {
        self.output
            .lock()
            .await
            .recv()
            .await
            .map(|line| (line.text, line.stream))
            .unzip()
    }

    async fn write(&self, data: &[u8]) -> std::io::Result<()> {
        let mut stdin = self.stdin.lock().await;
        let pipe = stdin
            .as_mut()
            .ok_or_else(|| std::io::Error::from(std::io::ErrorKind::BrokenPipe))?;
        pipe.write_all(data).await?;
        pipe.flush().await
    }

    async fn close(&self) {
        self.stdin.lock().await.take();
    }

    fn kill(&self) -> bool {
        self.kill.send(()).is_ok()
    }

    async fn wait(&self) -> Exit {
        let mut status = self.status.clone();
        let exit = status
            .wait_for(Option::is_some)
            .await
            .ok()
            .and_then(|exit| *exit);
        exit.unwrap_or(Exit::LOST)
    }
}

#[options]
struct SpawnOptions {
    cwd: Option<String>,
    env: Option<HashMap<String, String>>,
    stdio: Option<String>,
}

fn command(line: &[String], opts: SpawnOptions) -> std::io::Result<Command> {
    let Some((program, args)) = line.split_first() else {
        return Err(std::io::Error::other("proc.spawn needs a program"));
    };
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    match opts.stdio.as_deref() {
        None | Some("pipe") => {}
        Some("inherit") => {
            command
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit());
        }
        Some(other) => {
            return Err(std::io::Error::other(format!(
                "stdio must be \"pipe\" or \"inherit\", not {other:?}"
            )));
        }
    }
    if let Some(cwd) = opts.cwd {
        command.current_dir(cwd);
    }
    if let Some(env) = opts.env {
        command.envs(env);
    }
    Ok(command)
}

#[function(proc)]
fn spawn(argv: &[String], opts: SpawnOptions) -> std::io::Result<Proc> {
    let grouped = opts.stdio.as_deref() != Some("inherit");
    let mut command = command(argv, opts)?;
    if grouped {
        own_session(&mut command);
    }
    Ok(Proc::start(command.spawn()?, grouped))
}
