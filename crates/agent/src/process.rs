use std::collections::VecDeque;
use std::fmt::Write as _;
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::mpsc::UnboundedReceiver;

use crate::llm::CancelToken;

pub enum Program<'a> {
    Shell(&'a str),
    Argv(&'a [String]),
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Stream {
    Out,
    Err,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Exit {
    Code(i32),
    Cancelled,
    TimedOut,
}

pub struct Spec<'a> {
    program: Program<'a>,
    cwd: Option<&'a Path>,
    stdin: Option<UnboundedReceiver<Option<String>>>,
    timeout: Option<Duration>,
}

impl<'a> Spec<'a> {
    pub fn shell(command: &'a str) -> Self {
        Self {
            program: Program::Shell(command),
            cwd: None,
            stdin: None,
            timeout: None,
        }
    }

    pub fn argv(command: &'a [String]) -> Self {
        Self {
            program: Program::Argv(command),
            cwd: None,
            stdin: None,
            timeout: None,
        }
    }

    #[must_use]
    pub fn in_dir(mut self, cwd: &'a Path) -> Self {
        self.cwd = Some(cwd);
        self
    }

    #[must_use]
    pub fn writing(mut self, stdin: UnboundedReceiver<Option<String>>) -> Self {
        self.stdin = Some(stdin);
        self
    }

    #[must_use]
    pub fn within(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }
}

pub struct Capture {
    lines: VecDeque<String>,
    bytes: usize,
    budget: usize,
    dropped: usize,
    spill: Option<Spill>,
}

struct Spill {
    path: PathBuf,
    file: std::io::BufWriter<std::fs::File>,
}

impl Capture {
    pub fn new(budget: usize) -> Self {
        Self {
            lines: VecDeque::new(),
            bytes: 0,
            budget,
            dropped: 0,
            spill: None,
        }
    }

    #[must_use]
    pub fn spilling(mut self, path: PathBuf) -> Self {
        self.spill = std::fs::File::create(&path).ok().map(|file| Spill {
            path,
            file: std::io::BufWriter::new(file),
        });
        self
    }

    pub fn push(&mut self, line: &str) {
        if let Some(spill) = self.spill.as_mut()
            && writeln!(spill.file, "{line}").is_err()
        {
            self.spill = None;
        }
        self.bytes = self.bytes.saturating_add(line.len()).saturating_add(1);
        self.lines.push_back(line.to_string());
        while self.bytes > self.budget && self.lines.len() > 1 {
            let Some(gone) = self.lines.pop_front() else {
                break;
            };
            self.bytes = self.bytes.saturating_sub(gone.len().saturating_add(1));
            self.dropped = self.dropped.saturating_add(1);
        }
    }

    pub fn finish(mut self) -> String {
        let spilled = self
            .spill
            .take()
            .and_then(|mut spill| spill.file.flush().ok().map(|()| spill.path));
        let mut text = String::new();
        if self.dropped > 0 {
            let _ = write!(text, "… {} earlier lines dropped", self.dropped);
            match &spilled {
                Some(path) => {
                    let _ = writeln!(text, "; full output in {}", path.display());
                }
                None => text.push('\n'),
            }
        }
        let mut lines = self.lines.into_iter();
        if let Some(first) = lines.next() {
            text.push_str(&first);
        }
        for line in lines {
            text.push('\n');
            text.push_str(&line);
        }
        text
    }
}

fn builder(spec: &Spec<'_>) -> Option<tokio::process::Command> {
    let mut builder = match &spec.program {
        Program::Shell(command) => {
            let mut builder = tokio::process::Command::new("sh");
            builder.arg("-c").arg(command);
            builder
        }
        Program::Argv(words) => {
            let (program, args) = words.split_first()?;
            let mut builder = tokio::process::Command::new(program);
            builder.args(args);
            builder
        }
    };
    if let Some(cwd) = spec.cwd {
        builder.current_dir(cwd);
    }
    let stdin = if spec.stdin.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    };
    builder
        .stdin(stdin)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    Some(builder)
}

async fn next_line<R>(reader: &mut Option<tokio::io::Lines<BufReader<R>>>) -> Option<String>
where
    R: tokio::io::AsyncRead + Unpin,
{
    let lines = reader.as_mut()?;
    lines.next_line().await.ok().flatten()
}

pub async fn stream(
    spec: Spec<'_>,
    cancel: &CancelToken,
    mut on_line: impl FnMut(Stream, String),
) -> std::io::Result<Exit> {
    let Some(mut builder) = builder(&spec) else {
        return Err(std::io::Error::other("no program to run"));
    };
    let mut writes = spec.stdin;
    let mut child = builder.spawn()?;

    let mut stdout = child.stdout.take().map(|pipe| BufReader::new(pipe).lines());
    let mut stderr = child.stderr.take().map(|pipe| BufReader::new(pipe).lines());
    let mut stdin = child.stdin.take();
    let deadline = spec
        .timeout
        .map(|after| tokio::time::Instant::now() + after);

    loop {
        let timer = async {
            match deadline {
                Some(at) => tokio::time::sleep_until(at).await,
                None => std::future::pending().await,
            }
        };
        tokio::select! {
            line = next_line(&mut stdout), if stdout.is_some() => match line {
                Some(line) => on_line(Stream::Out, line),
                None => stdout = None,
            },
            line = next_line(&mut stderr), if stderr.is_some() => match line {
                Some(line) => on_line(Stream::Err, line),
                None => stderr = None,
            },
            write = async { writes.as_mut()?.recv().await }, if writes.is_some() && stdin.is_some() => {
                match write {
                    Some(Some(data)) => {
                        if let Some(pipe) = stdin.as_mut()
                            && pipe.write_all(data.as_bytes()).await.is_err()
                        {
                            stdin = None;
                        }
                    }
                    _ => stdin = None,
                }
            }
            status = child.wait(), if stdout.is_none() && stderr.is_none() => {
                let code = status.ok().and_then(|status| status.code()).unwrap_or(-1);
                return Ok(Exit::Code(code));
            }
            () = cancel.cancelled() => {
                let _ = child.kill().await;
                return Ok(Exit::Cancelled);
            }
            () = timer => {
                let _ = child.kill().await;
                return Ok(Exit::TimedOut);
            }
        }
    }
}
