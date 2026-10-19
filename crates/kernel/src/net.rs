use std::collections::HashMap;
use std::io::Write;
use std::sync::{Arc, LazyLock};
use std::time::Duration;

use brotli::enc::BrotliEncoderParams;
use bytes::{Buf, Bytes, BytesMut};
use flate2::Compression;
use flate2::write::{GzEncoder, ZlibEncoder};
use futures_util::StreamExt;
use mlua::{BString, Lua, Table};
use reqwest::header::{CONTENT_ENCODING, HeaderMap, HeaderName, HeaderValue};
use reqwest::{Client, Method};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpListener;
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::sync::mpsc::error::TryRecvError;
use tokio::sync::{Mutex, mpsc, oneshot};
use uji_macros::{function, methods, options, value};

use crate::io::{Abort, Line};

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const READ_TIMEOUT: Duration = Duration::from_secs(150);
const IDLE: Duration = Duration::from_secs(120);
const CHUNKS: usize = 64;
const NEWLINE: u8 = b'\n';
const RETURN: u8 = b'\r';
const LOOPBACK: &str = "127.0.0.1";
const MIN_PACKED: usize = 1024;
const ZSTD: i32 = 3;

#[derive(Clone, Copy)]
enum Encoding {
    Gzip,
    Deflate,
    Zstd,
    Brotli,
}

impl Encoding {
    fn parse(name: &str) -> Result<Self, NetError> {
        match name {
            "gzip" => Ok(Self::Gzip),
            "deflate" => Ok(Self::Deflate),
            "zstd" => Ok(Self::Zstd),
            "br" => Ok(Self::Brotli),
            _ => Err(NetError::Invalid(format!(
                "unknown content encoding {name}"
            ))),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Gzip => "gzip",
            Self::Deflate => "deflate",
            Self::Zstd => "zstd",
            Self::Brotli => "br",
        }
    }

    fn pack(self, body: &[u8]) -> Result<Vec<u8>, NetError> {
        match self {
            Self::Gzip => {
                let mut packer = GzEncoder::new(Vec::new(), Compression::default());
                packer.write_all(body)?;
                Ok(packer.finish()?)
            }
            Self::Deflate => {
                let mut packer = ZlibEncoder::new(Vec::new(), Compression::default());
                packer.write_all(body)?;
                Ok(packer.finish()?)
            }
            Self::Zstd => Ok(zstd::stream::encode_all(body, ZSTD)?),
            Self::Brotli => {
                let mut packed = Vec::new();
                let mut source = body;
                brotli::BrotliCompress(&mut source, &mut packed, &BrotliEncoderParams::default())?;
                Ok(packed)
            }
        }
    }
}

static CLIENT: LazyLock<Client> = LazyLock::new(|| {
    Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .read_timeout(READ_TIMEOUT)
        .build()
        .unwrap_or_default()
});

pub(crate) fn warm() {
    LazyLock::force(&CLIENT);
}

#[derive(Debug, thiserror::Error)]
enum NetError {
    #[error("{0}")]
    Request(#[from] reqwest::Error),
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Invalid(String),
    #[error("no data arrived for {0} seconds")]
    Idle(u64),
    #[error("the request stopped before it answered")]
    Stopped,
    #[error("the server is closed")]
    Closed,
}

fn seconds(value: Option<f64>, key: &str) -> Result<Option<Duration>, NetError> {
    value
        .map(|value| {
            Duration::try_from_secs_f64(value)
                .map_err(|_| NetError::Invalid(format!("{key} needs a number of seconds")))
        })
        .transpose()
}

#[options]
struct RequestOptions {
    url: String,
    method: Option<String>,
    #[serde(default)]
    headers: HashMap<String, String>,
    body: Option<String>,
    encoding: Option<String>,
    timeout: Option<f64>,
    idle: Option<f64>,
}

struct Request {
    method: Method,
    url: reqwest::Url,
    headers: HeaderMap,
    body: Option<String>,
    encoding: Option<Encoding>,
    timeout: Option<Duration>,
    idle: Duration,
}

impl Request {
    fn new(opts: RequestOptions) -> Result<Self, NetError> {
        let method = opts.method.map_or(Ok(Method::GET), |method| {
            Method::from_bytes(method.to_ascii_uppercase().as_bytes())
                .map_err(|_| NetError::Invalid(format!("invalid method {method}")))
        })?;
        let url = reqwest::Url::parse(&opts.url)
            .map_err(|err| NetError::Invalid(format!("invalid url {}: {err}", opts.url)))?;
        let headers = opts
            .headers
            .into_iter()
            .map(|(name, value)| {
                let invalid = || NetError::Invalid(format!("invalid header {name}"));
                Ok((
                    HeaderName::try_from(name.as_str()).map_err(|_| invalid())?,
                    HeaderValue::try_from(value.as_str()).map_err(|_| invalid())?,
                ))
            })
            .collect::<Result<HeaderMap, NetError>>()?;
        Ok(Self {
            method,
            url,
            headers,
            body: opts.body,
            encoding: opts.encoding.as_deref().map(Encoding::parse).transpose()?,
            timeout: seconds(opts.timeout, "timeout")?,
            idle: seconds(opts.idle, "idle")?.unwrap_or(IDLE),
        })
    }

    fn build(self) -> Result<reqwest::RequestBuilder, NetError> {
        let mut builder = CLIENT.request(self.method, self.url).headers(self.headers);
        if let Some(body) = self.body {
            let bytes = match self.encoding {
                Some(encoding) if body.len() >= MIN_PACKED => {
                    builder =
                        builder.header(CONTENT_ENCODING, HeaderValue::from_static(encoding.name()));
                    encoding.pack(body.as_bytes())?
                }
                _ => body.into_bytes(),
            };
            builder = builder.body(bytes);
        }
        if let Some(timeout) = self.timeout {
            builder = builder.timeout(timeout);
        }
        Ok(builder)
    }
}

#[value]
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

#[value]
struct Response {
    #[serde(flatten)]
    head: Head,
    body: String,
}

async fn stream(
    request: Request,
    head: oneshot::Sender<Result<Head, NetError>>,
    chunks: mpsc::Sender<Result<Bytes, NetError>>,
) {
    let idle = request.idle;
    let sent = match request.build() {
        Ok(builder) => builder.send().await.map_err(NetError::from),
        Err(err) => Err(err),
    };
    let response = match sent {
        Ok(response) => response,
        Err(err) => {
            drop(head.send(Err(err)));
            return;
        }
    };
    if head.send(Ok(Head::of(&response))).is_err() {
        return;
    }
    let mut body = response.bytes_stream();
    loop {
        let next = match tokio::time::timeout(idle, body.next()).await {
            Ok(Some(chunk)) => chunk.map_err(NetError::from),
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
    receiver: mpsc::Receiver<Result<Bytes, NetError>>,
    buffer: BytesMut,
    done: bool,
}

enum Ready {
    Line(Bytes),
    End,
    Wait,
}

impl Chunks {
    fn fill(&mut self, chunk: &[u8]) {
        self.buffer.extend_from_slice(chunk);
    }

    fn split(&mut self) -> Option<Bytes> {
        let end = memchr::memchr(NEWLINE, &self.buffer)?;
        let mut line = self.buffer.split_to(end);
        self.buffer.advance(1);
        if line.last() == Some(&RETURN) {
            line.truncate(line.len() - 1);
        }
        Some(line.freeze())
    }

    fn remainder(&mut self) -> Option<Bytes> {
        (!self.buffer.is_empty()).then(|| std::mem::take(&mut self.buffer).freeze())
    }

    fn ready(&mut self) -> Result<Ready, NetError> {
        loop {
            if let Some(line) = self.split() {
                return Ok(Ready::Line(line));
            }
            if self.done {
                return Ok(self.remainder().map_or(Ready::End, Ready::Line));
            }
            match self.receiver.try_recv() {
                Ok(chunk) => self.fill(&chunk?),
                Err(TryRecvError::Empty) => return Ok(Ready::Wait),
                Err(TryRecvError::Disconnected) => self.done = true,
            }
        }
    }

    async fn line(&mut self) -> Result<Option<Bytes>, NetError> {
        loop {
            if let Some(line) = self.split() {
                return Ok(Some(line));
            }
            if self.done {
                return Ok(self.remainder());
            }
            self.pull().await?;
        }
    }

    async fn rest(&mut self) -> Result<Bytes, NetError> {
        while !self.done {
            self.pull().await?;
        }
        Ok(self.remainder().unwrap_or_default())
    }

    async fn pull(&mut self) -> Result<(), NetError> {
        match self.receiver.recv().await {
            Some(chunk) => self.fill(&chunk?),
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

#[methods]
impl Body {
    #[get]
    fn status(&self) -> u16 {
        self.head.status
    }

    #[get]
    fn headers(&self, lua: &Lua) -> mlua::Result<Table> {
        lua.create_table_from(
            self.head
                .headers
                .iter()
                .map(|(name, value)| (name.as_str(), value.as_str())),
        )
    }

    #[iterate(lines)]
    async fn line(&self, wait: Option<f64>) -> Result<Line, NetError> {
        let limit = seconds(wait, "wait")?;
        let mut chunks = self.chunks.lock().await;
        match chunks.ready()? {
            Ready::Line(line) => Ok(Line::Text(line.as_ref().into())),
            Ready::End => Ok(Line::End),
            Ready::Wait => Line::within(limit, chunks.line()).await,
        }
    }

    async fn read(&self) -> Result<BString, NetError> {
        self.chunks
            .lock()
            .await
            .rest()
            .await
            .map(|body| BString::from(body.as_ref()))
    }
}

#[value]
struct Url {
    uri: String,
    scheme: String,
    host: String,
    port: Option<u16>,
    path: String,
    query: Option<String>,
    fragment: Option<String>,
}

#[function(net)]
fn url(text: &str) -> Option<Url> {
    let parsed = reqwest::Url::parse(text).ok()?;
    let host = parsed.host_str().filter(|host| !host.is_empty())?;
    Some(Url {
        uri: parsed.as_str().to_string(),
        scheme: parsed.scheme().to_string(),
        host: host.to_string(),
        port: parsed.port(),
        path: parsed.path().to_string(),
        query: parsed.query().map(str::to_string),
        fragment: parsed.fragment().map(str::to_string),
    })
}

#[function(net)]
async fn request(opts: RequestOptions) -> Result<Response, NetError> {
    let response = Request::new(opts)?.build()?.send().await?;
    let head = Head::of(&response);
    let body = response.text().await?;
    Ok(Response { head, body })
}

#[function(net)]
async fn open(opts: RequestOptions) -> Result<Body, NetError> {
    let request = Request::new(opts)?;
    let (head, answered) = oneshot::channel();
    let (chunks, receiver) = mpsc::channel(CHUNKS);
    let task = tokio::spawn(stream(request, head, chunks));
    let guard = Abort(task.abort_handle());
    let head = answered.await.unwrap_or(Err(NetError::Stopped))?;
    Ok(Body {
        head,
        chunks: Mutex::new(Chunks {
            receiver,
            buffer: BytesMut::new(),
            done: false,
        }),
        _task: guard,
    })
}

pub(crate) struct Server {
    port: u16,
    listener: Mutex<Option<Arc<TcpListener>>>,
}

#[methods]
impl Server {
    #[get]
    fn port(&self) -> u16 {
        self.port
    }

    async fn accept(&self) -> Result<Conn, NetError> {
        let listener = self.listener.lock().await.clone().ok_or(NetError::Closed)?;
        let (stream, _) = listener.accept().await?;
        let (reader, writer) = stream.into_split();
        Ok(Conn {
            reader: Mutex::new(BufReader::new(reader)),
            writer: Mutex::new(writer),
        })
    }

    async fn close(&self) {
        self.listener.lock().await.take();
    }
}

#[function(net)]
async fn listen(port: Option<u16>) -> Result<Server, NetError> {
    let listener = TcpListener::bind((LOOPBACK, port.unwrap_or(0))).await?;
    Ok(Server {
        port: listener.local_addr()?.port(),
        listener: Mutex::new(Some(Arc::new(listener))),
    })
}

pub(crate) struct Conn {
    reader: Mutex<BufReader<OwnedReadHalf>>,
    writer: Mutex<OwnedWriteHalf>,
}

async fn read_line(reader: &mut BufReader<OwnedReadHalf>) -> std::io::Result<Option<Vec<u8>>> {
    let mut line = String::new();
    if reader.read_line(&mut line).await? == 0 {
        return Ok(None);
    }
    line.truncate(line.trim_end_matches(['\r', '\n']).len());
    Ok(Some(line.into_bytes()))
}

#[methods]
impl Conn {
    async fn line(&self, wait: Option<f64>) -> Result<Line, NetError> {
        let limit = seconds(wait, "wait")?;
        let mut reader = self.reader.lock().await;
        Ok(Line::within(limit, read_line(&mut reader)).await?)
    }

    async fn read(&self, count: usize) -> Result<BString, NetError> {
        let mut buffer = vec![0; count];
        self.reader.lock().await.read_exact(&mut buffer).await?;
        Ok(buffer.into())
    }

    async fn write(&self, data: &[u8]) -> Result<(), NetError> {
        let mut writer = self.writer.lock().await;
        writer.write_all(data).await?;
        writer.flush().await?;
        Ok(())
    }

    async fn close(&self) -> Result<(), NetError> {
        self.writer.lock().await.shutdown().await?;
        Ok(())
    }
}
