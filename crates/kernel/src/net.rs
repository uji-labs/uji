use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use std::pin::pin;

use futures_util::StreamExt;
use futures_util::future::{self, Either};
use mlua::{
    AnyUserData, Function, IntoLuaMulti, Lua, LuaSerdeExt, MultiValue, ObjectLike, Table, UserData,
    UserDataFields, UserDataMethods, Value,
};
use reqwest::header::{HeaderMap, HeaderName, HeaderValue};
use reqwest::{Client, Method, Url};
use serde::Serialize;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::sync::{Mutex, mpsc, oneshot};

use crate::io::{self, Abort};
use crate::kernel::State;

const IDLE: Duration = Duration::from_secs(120);
const CHUNKS: usize = 64;
const NEWLINE: u8 = b'\n';
const RETURN: u8 = b'\r';
const LOOPBACK: &str = "127.0.0.1";

#[derive(Debug, thiserror::Error)]
enum NetError {
    #[error("{0}")]
    Request(#[from] reqwest::Error),
    #[error("no data arrived for {0} seconds")]
    Idle(u64),
    #[error("the request stopped before it answered")]
    Stopped,
}

struct Request {
    method: Method,
    url: Url,
    headers: HeaderMap,
    body: Option<Vec<u8>>,
    timeout: Option<Duration>,
    idle: Duration,
}

fn seconds(opts: &Table, key: &str) -> mlua::Result<Option<Duration>> {
    opts.get::<Option<f64>>(key)?
        .map(|value| {
            Duration::try_from_secs_f64(value)
                .map_err(|_| mlua::Error::runtime(format!("{key} needs a number of seconds")))
        })
        .transpose()
}

impl Request {
    fn from_table(opts: &Table) -> mlua::Result<Self> {
        let method = opts
            .get::<Option<String>>("method")?
            .map_or(Ok(Method::GET), |method| {
                Method::from_bytes(method.to_ascii_uppercase().as_bytes())
                    .map_err(|_| mlua::Error::runtime(format!("invalid method {method}")))
            })?;
        let url = opts.get::<String>("url")?;
        let url = Url::parse(&url)
            .map_err(|err| mlua::Error::runtime(format!("invalid url {url}: {err}")))?;
        let headers = opts
            .get::<Option<HashMap<String, String>>>("headers")?
            .unwrap_or_default()
            .into_iter()
            .map(|(name, value)| {
                let invalid = || mlua::Error::runtime(format!("invalid header {name}"));
                Ok((
                    HeaderName::try_from(name.as_str()).map_err(|_| invalid())?,
                    HeaderValue::try_from(value.as_str()).map_err(|_| invalid())?,
                ))
            })
            .collect::<mlua::Result<HeaderMap>>()?;
        Ok(Self {
            method,
            url,
            headers,
            body: opts
                .get::<Option<mlua::LuaString>>("body")?
                .map(|body| body.as_bytes().to_vec()),
            timeout: seconds(opts, "timeout")?,
            idle: seconds(opts, "idle")?.unwrap_or(IDLE),
        })
    }

    fn build(self, client: &Client) -> reqwest::RequestBuilder {
        let mut builder = client.request(self.method, self.url).headers(self.headers);
        if let Some(body) = self.body {
            builder = builder.body(body);
        }
        if let Some(timeout) = self.timeout {
            builder = builder.timeout(timeout);
        }
        builder
    }
}

#[derive(Serialize)]
struct Head {
    status: u16,
    headers: HashMap<String, String>,
}

impl Head {
    fn of(response: &reqwest::Response) -> Self {
        Self {
            status: response.status().as_u16(),
            headers: response
                .headers()
                .iter()
                .filter_map(|(name, value)| {
                    value
                        .to_str()
                        .ok()
                        .map(|value| (name.as_str().to_string(), value.to_string()))
                })
                .collect(),
        }
    }
}

#[derive(Serialize)]
struct Response {
    #[serde(flatten)]
    head: Head,
    body: String,
}

async fn fetch(client: Client, request: Request) -> Result<Response, NetError> {
    let response = request.build(&client).send().await?;
    let head = Head::of(&response);
    let body = response.text().await?;
    Ok(Response { head, body })
}

async fn stream(
    client: Client,
    request: Request,
    head: oneshot::Sender<Result<Head, NetError>>,
    chunks: mpsc::Sender<Result<Vec<u8>, NetError>>,
) {
    let idle = request.idle;
    let response = match request.build(&client).send().await {
        Ok(response) => response,
        Err(err) => {
            drop(head.send(Err(err.into())));
            return;
        }
    };
    if head.send(Ok(Head::of(&response))).is_err() {
        return;
    }
    let mut body = response.bytes_stream();
    loop {
        let next = match tokio::time::timeout(idle, body.next()).await {
            Ok(Some(chunk)) => chunk.map(|chunk| chunk.to_vec()).map_err(NetError::from),
            Ok(None) => return,
            Err(_) => Err(NetError::Idle(idle.as_secs())),
        };
        let failed = next.is_err();
        if chunks.send(next).await.is_err() || failed {
            return;
        }
    }
}

struct Chunks {
    receiver: mpsc::Receiver<Result<Vec<u8>, NetError>>,
    buffer: Vec<u8>,
    done: bool,
}

impl Chunks {
    async fn line(&mut self) -> Result<Option<Vec<u8>>, NetError> {
        loop {
            if let Some(at) = self.buffer.iter().position(|byte| *byte == NEWLINE) {
                let mut line: Vec<u8> = self.buffer.drain(..=at).collect();
                line.pop();
                if line.last() == Some(&RETURN) {
                    line.pop();
                }
                return Ok(Some(line));
            }
            if self.done {
                return Ok((!self.buffer.is_empty()).then(|| std::mem::take(&mut self.buffer)));
            }
            self.pull().await?;
        }
    }

    async fn rest(&mut self) -> Result<Vec<u8>, NetError> {
        while !self.done {
            self.pull().await?;
        }
        Ok(std::mem::take(&mut self.buffer))
    }

    async fn pull(&mut self) -> Result<(), NetError> {
        match self.receiver.recv().await {
            Some(chunk) => self.buffer.extend(chunk?),
            None => self.done = true,
        }
        Ok(())
    }
}

pub(crate) struct Body {
    head: Head,
    chunks: Mutex<Chunks>,
    _task: Abort,
}

impl UserData for Body {
    fn add_fields<F: UserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("status", |_, body| Ok(body.head.status));
        fields.add_field_method_get("headers", |lua, body| lua.to_value(&body.head.headers));
    }

    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_async_method("line", |lua, body, wait: Option<f64>| async move {
            let limit = wait
                .map(|seconds| {
                    Duration::try_from_secs_f64(seconds)
                        .map_err(|_| mlua::Error::runtime("line needs a number of seconds"))
                })
                .transpose()?;
            let mut chunks = body.chunks.lock().await;
            let read = match limit {
                None => chunks.line().await,
                Some(limit) => {
                    let timer = io::run(io::handle(&lua)?, async move {
                        tokio::time::sleep(limit).await;
                    });
                    match future::select(pin!(chunks.line()), pin!(timer)).await {
                        Either::Left((read, _)) => read,
                        Either::Right((slept, _)) => {
                            slept?;
                            return Value::Boolean(false).into_lua_multi(&lua);
                        }
                    }
                }
            };
            match read {
                Ok(Some(line)) => Value::String(lua.create_string(line)?).into_lua_multi(&lua),
                Ok(None) => Ok(MultiValue::new()),
                Err(err) => io::failure(&lua, &err),
            }
        });
        methods.add_function("lines", |_, body: AnyUserData| {
            let line: Function = body.get("line")?;
            Ok((line, body))
        });
        methods.add_async_method("read", |lua, body, ()| async move {
            match body.chunks.lock().await.rest().await {
                Ok(rest) => Value::String(lua.create_string(rest)?).into_lua_multi(&lua),
                Err(err) => io::failure(&lua, &err),
            }
        });
    }
}

async fn open(lua: Lua, request: Request) -> mlua::Result<MultiValue> {
    let io = io::handle(&lua)?;
    let client = State::of(&lua)?.client();
    let (head, answered) = oneshot::channel();
    let (chunks, receiver) = mpsc::channel(CHUNKS);
    let task = io.spawn(stream(client, request, head, chunks));
    let guard = Abort(task.abort_handle());
    match answered.await.unwrap_or(Err(NetError::Stopped)) {
        Ok(head) => Body {
            head,
            chunks: Mutex::new(Chunks {
                receiver,
                buffer: Vec::new(),
                done: false,
            }),
            _task: guard,
        }
        .into_lua_multi(&lua),
        Err(err) => io::failure(&lua, &err),
    }
}

pub(crate) struct Server {
    port: u16,
    listener: Mutex<Option<Arc<TcpListener>>>,
}

pub(crate) struct Conn {
    reader: Arc<Mutex<BufReader<OwnedReadHalf>>>,
    writer: Arc<Mutex<OwnedWriteHalf>>,
}

async fn read_line(
    reader: Arc<Mutex<BufReader<OwnedReadHalf>>>,
) -> std::io::Result<Option<String>> {
    let mut line = String::new();
    if reader.lock().await.read_line(&mut line).await? == 0 {
        return Ok(None);
    }
    Ok(Some(line.trim_end_matches(['\r', '\n']).to_string()))
}

async fn read_exact(
    reader: Arc<Mutex<BufReader<OwnedReadHalf>>>,
    count: usize,
) -> std::io::Result<Vec<u8>> {
    let mut buffer = vec![0; count];
    reader.lock().await.read_exact(&mut buffer).await?;
    Ok(buffer)
}

async fn write_all(writer: Arc<Mutex<OwnedWriteHalf>>, data: Vec<u8>) -> std::io::Result<()> {
    let mut writer = writer.lock().await;
    writer.write_all(&data).await?;
    writer.flush().await
}

async fn shutdown(writer: Arc<Mutex<OwnedWriteHalf>>) -> std::io::Result<()> {
    writer.lock().await.shutdown().await
}

impl UserData for Server {
    fn add_fields<F: UserDataFields<Self>>(fields: &mut F) {
        fields.add_field_method_get("port", |_, server| Ok(server.port));
    }

    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_async_method("accept", |lua, server, ()| async move {
            let Some(listener) = server.listener.lock().await.clone() else {
                return io::failure(&lua, &"the server is closed");
            };
            let accepted =
                io::run(io::handle(&lua)?, async move { listener.accept().await }).await?;
            match accepted {
                Ok((stream, _)) => {
                    let (reader, writer) = stream.into_split();
                    Conn {
                        reader: Arc::new(Mutex::new(BufReader::new(reader))),
                        writer: Arc::new(Mutex::new(writer)),
                    }
                    .into_lua_multi(&lua)
                }
                Err(err) => io::failure(&lua, &err),
            }
        });
        methods.add_async_method("close", |_, server, ()| async move {
            server.listener.lock().await.take();
            Ok(())
        });
    }
}

impl UserData for Conn {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_async_method("line", |lua, conn, ()| async move {
            let read = io::run(io::handle(&lua)?, read_line(Arc::clone(&conn.reader))).await?;
            io::settle(&lua, read)
        });
        methods.add_async_method("read", |lua, conn, count: usize| async move {
            let read = io::run(
                io::handle(&lua)?,
                read_exact(Arc::clone(&conn.reader), count),
            )
            .await?;
            match read {
                Ok(bytes) => Value::String(lua.create_string(bytes)?).into_lua_multi(&lua),
                Err(err) => io::failure(&lua, &err),
            }
        });
        methods.add_async_method("write", |lua, conn, data: mlua::LuaString| async move {
            let bytes = data.as_bytes().to_vec();
            let written = io::run(
                io::handle(&lua)?,
                write_all(Arc::clone(&conn.writer), bytes),
            )
            .await?;
            io::settle(&lua, written.map(|()| true))
        });
        methods.add_async_method("close", |lua, conn, ()| async move {
            let closed = io::run(io::handle(&lua)?, shutdown(Arc::clone(&conn.writer))).await?;
            io::settle(&lua, closed.map(|()| true))
        });
    }
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let net = lua.create_table()?;
    net.set(
        "request",
        lua.create_async_function(|lua, opts: Table| async move {
            let request = Request::from_table(&opts)?;
            let client = State::of(&lua)?.client();
            let fetched = io::run(io::handle(&lua)?, fetch(client, request)).await?;
            match fetched {
                Ok(response) => lua.to_value(&response)?.into_lua_multi(&lua),
                Err(err) => io::failure(&lua, &err),
            }
        })?,
    )?;
    net.set(
        "open",
        lua.create_async_function(|lua, opts: Table| async move {
            let request = Request::from_table(&opts)?;
            open(lua, request).await
        })?,
    )?;
    net.set(
        "listen",
        lua.create_async_function(|lua, port: Option<u16>| async move {
            let bound = io::run(
                io::handle(&lua)?,
                TcpListener::bind((LOOPBACK, port.unwrap_or(0))),
            )
            .await?;
            match bound.and_then(|listener| Ok((listener.local_addr()?.port(), listener))) {
                Ok((port, listener)) => Server {
                    port,
                    listener: Mutex::new(Some(Arc::new(listener))),
                }
                .into_lua_multi(&lua),
                Err(err) => io::failure(&lua, &err),
            }
        })?,
    )?;
    Ok(net)
}
