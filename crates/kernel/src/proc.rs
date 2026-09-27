use std::collections::HashMap;
use std::process::{ExitStatus, Stdio};
use std::sync::Arc;

use mlua::{
    AnyUserData, Function, IntoLuaMulti, Lua, LuaSerdeExt, MultiValue, ObjectLike, Table, UserData,
    UserDataFields, UserDataMethods,
};
use serde::Serialize;
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStdin, Command};
use tokio::runtime::Handle;
use tokio::sync::{Mutex, mpsc, watch};

use crate::io;

const NEWLINE: u8 = b'\n';
const RETURN: u8 = b'\r';

struct Line {
    stream: &'static str,
    text: String,
}

#[derive(Clone, Copy, Serialize)]
struct Exit {
    code: Option<i32>,
    signal: Option<i32>,
    success: bool,
}

impl Exit {
    fn of(status: &std::io::Result<ExitStatus>) -> Self {
        let Ok(status) = status else {
            return Self {
                code: None,
                signal: None,
                success: false,
            };
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
    stdin: Arc<Mutex<Option<ChildStdin>>>,
    output: Mutex<mpsc::UnboundedReceiver<Line>>,
    status: watch::Receiver<Option<Exit>>,
    kill: mpsc::UnboundedSender<()>,
}

impl Proc {
    fn start(io: &Handle, mut child: Child) -> Self {
        let (lines, output) = mpsc::unbounded_channel();
        if let Some(stdout) = child.stdout.take() {
            io.spawn(pipe(stdout, "stdout", lines.clone()));
        }
        if let Some(stderr) = child.stderr.take() {
            io.spawn(pipe(stderr, "stderr", lines));
        }
        let (report, status) = watch::channel(None);
        let (kill, killed) = mpsc::unbounded_channel();
        let pid = child.id();
        let stdin = child.stdin.take();
        io.spawn(supervise(child, killed, report));
        Self {
            pid,
            stdin: Arc::new(Mutex::new(stdin)),
            output: Mutex::new(output),
            status,
            kill,
        }
    }
}

async fn pipe(
    reader: impl AsyncRead + Unpin,
    stream: &'static str,
    lines: mpsc::UnboundedSender<Line>,
) {
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

async fn supervise(
    mut child: Child,
    mut killed: mpsc::UnboundedReceiver<()>,
    report: watch::Sender<Option<Exit>>,
) {
    let status = tokio::select! {
        status = child.wait() => status,
        _ = killed.recv() => {
            drop(child.start_kill());
            child.wait().await
        }
    };
    report.send_replace(Some(Exit::of(&status)));
}

async fn write(stdin: Arc<Mutex<Option<ChildStdin>>>, data: Vec<u8>) -> std::io::Result<()> {
    let mut stdin = stdin.lock().await;
    let pipe = stdin
        .as_mut()
        .ok_or_else(|| std::io::Error::from(std::io::ErrorKind::BrokenPipe))?;
    pipe.write_all(&data).await?;
    pipe.flush().await
}

impl UserData for Proc {
    fn add_fields<F: UserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("pid", |_, proc| Ok(proc.pid));
    }

    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_async_method("line", |lua, proc, ()| async move {
            match proc.output.lock().await.recv().await {
                Some(line) => (line.text, line.stream).into_lua_multi(&lua),
                None => Ok(MultiValue::new()),
            }
        });
        methods.add_function("lines", |_, proc: AnyUserData| {
            let line: Function = proc.get("line")?;
            Ok((line, proc))
        });
        methods.add_async_method("write", |lua, proc, data: mlua::LuaString| async move {
            let stdin = Arc::clone(&proc.stdin);
            let bytes = data.as_bytes().to_vec();
            let written = io::run(io::handle(&lua)?, write(stdin, bytes)).await?;
            io::settle(&lua, written.map(|()| true))
        });
        methods.add_async_method("close", |_, proc, ()| async move {
            proc.stdin.lock().await.take();
            Ok(())
        });
        methods.add_method("kill", |_, proc, ()| Ok(proc.kill.send(()).is_ok()));
        methods.add_async_method("wait", |lua, proc, ()| async move {
            let mut status = proc.status.clone();
            let exit = status
                .wait_for(Option::is_some)
                .await
                .map_err(mlua::Error::external)?
                .unwrap_or(Exit {
                    code: None,
                    signal: None,
                    success: false,
                });
            lua.to_value(&exit)
        });
    }
}

fn command(line: &[String], opts: Option<&Table>) -> mlua::Result<Command> {
    let Some((program, args)) = line.split_first() else {
        return Err(mlua::Error::runtime("proc.spawn needs a program"));
    };
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    let Some(opts) = opts else {
        return Ok(command);
    };
    match opts.get::<Option<String>>("stdio")?.as_deref() {
        None | Some("pipe") => {}
        Some("inherit") => {
            command
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit());
        }
        Some(other) => {
            return Err(mlua::Error::runtime(format!(
                "stdio must be \"pipe\" or \"inherit\", not {other:?}"
            )));
        }
    }
    if let Some(cwd) = opts.get::<Option<String>>("cwd")? {
        command.current_dir(cwd);
    }
    if let Some(env) = opts.get::<Option<HashMap<String, String>>>("env")? {
        command.envs(env);
    }
    Ok(command)
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let proc = lua.create_table()?;
    proc.set(
        "spawn",
        lua.create_function(|lua, (argv, opts): (Vec<String>, Option<Table>)| {
            let mut command = command(&argv, opts.as_ref())?;
            let io = io::handle(lua)?;
            let entered = io.enter();
            let spawned = command.spawn();
            drop(entered);
            match spawned {
                Ok(child) => Proc::start(&io, child).into_lua_multi(lua),
                Err(err) => io::failure(lua, &err),
            }
        })?,
    )?;
    Ok(proc)
}
