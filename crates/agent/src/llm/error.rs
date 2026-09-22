use std::time::Duration;

use futures_util::StreamExt;
use serde::Serialize;

pub(crate) async fn send<T: Serialize + ?Sized>(
    builder: reqwest::RequestBuilder,
    request: &T,
) -> Result<reqwest::Response, LlmError> {
    builder
        .json(request)
        .send()
        .await
        .map_err(LlmError::transport)
}

#[derive(Debug, thiserror::Error)]
pub enum LlmError {
    #[error("http: {0}")]
    Http(HttpError),
    #[error("authentication rejected ({0}) - check the api key for this provider")]
    Auth(u16),
    #[error("provider: {0}")]
    Provider(String),
}

const MAX_ERROR_BODY: usize = 2_000;

#[derive(Debug, Clone)]
pub struct HttpError {
    pub status: Option<u16>,
    pub retry_after: Option<Duration>,
    pub body: String,
}

impl std::fmt::Display for HttpError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self.status {
            Some(status) => write!(f, "{status}: {}", self.body),
            None => f.write_str(&self.body),
        }
    }
}

impl HttpError {
    fn retryable(&self) -> bool {
        match self.status {
            None | Some(408 | 409 | 425 | 429) => true,
            Some(status) => (500..600).contains(&status),
        }
    }
}

impl LlmError {
    pub(crate) fn stalled(after: Duration) -> Self {
        Self::transport(format!(
            "the provider sent nothing for {}s",
            after.as_secs()
        ))
    }

    pub(crate) fn truncated_stream() -> Self {
        Self::transport("the provider closed the stream before the reply finished")
    }

    pub(crate) fn transport(err: impl std::fmt::Display) -> Self {
        Self::Http(HttpError {
            status: None,
            retry_after: None,
            body: err.to_string(),
        })
    }

    pub fn retryable(&self) -> bool {
        match self {
            Self::Http(http) => http.retryable(),
            Self::Auth(_) | Self::Provider(_) => false,
        }
    }

    pub fn retry_after(&self) -> Option<Duration> {
        match self {
            Self::Http(http) => http.retry_after,
            Self::Auth(_) | Self::Provider(_) => None,
        }
    }

    pub(crate) fn truncated_call(name: &str) -> Self {
        Self::Provider(format!(
            "the reply was cut off while calling `{name}`, so its arguments are incomplete - raise the model's max output"
        ))
    }

    pub(crate) fn output_limit() -> Self {
        Self::Provider("response hit the model's output limit and was cut off".into())
    }

    pub(crate) fn empty_response() -> Self {
        Self::Provider("empty response".into())
    }
}

pub(crate) async fn status_error(response: reqwest::Response) -> LlmError {
    let status = response.status().as_u16();
    let retry_after = retry_after(response.headers());
    let body = response.text().await.unwrap_or_default();
    if status == 401 || status == 403 {
        LlmError::Auth(status)
    } else {
        LlmError::Http(HttpError {
            status: Some(status),
            retry_after,
            body: clip(body.trim(), MAX_ERROR_BODY),
        })
    }
}

fn retry_after(headers: &reqwest::header::HeaderMap) -> Option<Duration> {
    let value = headers.get(reqwest::header::RETRY_AFTER)?.to_str().ok()?;
    let seconds = value.trim().parse::<u64>().ok()?;
    Some(Duration::from_secs(seconds.min(MAX_RETRY_AFTER_SECS)))
}

pub(crate) fn clip(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let head: String = text.chars().take(max).collect();
    format!(
        "{head}\n… [truncated, {max} of {} chars shown]",
        text.chars().count()
    )
}

pub(crate) const STREAM_IDLE: Duration = Duration::from_secs(120);

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

const TRANSPORT_IDLE: Duration = Duration::from_secs(STREAM_IDLE.as_secs() + 30);

pub fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .read_timeout(TRANSPORT_IDLE)
        .build()
        .unwrap_or_default()
}

pub(crate) const MAX_RETRY_AFTER_SECS: u64 = 60;
pub(crate) const RETRY_ATTEMPTS: u32 = 5;
const RETRY_INITIAL: Duration = Duration::from_secs(2);
const RETRY_FACTOR: u32 = 2;
const RETRY_JITTER: f64 = 0.25;
const RETRY_CEILING: Duration = Duration::from_secs(30);

pub(crate) fn backoff(attempt: u32) -> Duration {
    let step = RETRY_INITIAL.saturating_mul(RETRY_FACTOR.saturating_pow(attempt));
    let capped = step.min(RETRY_CEILING);
    let jitter = 1.0 + RETRY_JITTER * (rand::random::<f64>() * 2.0 - 1.0);
    capped.mul_f64(jitter.max(0.0))
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum Progress {
    Made,
    Keepalive,
}

pub(crate) async fn response_lines(
    response: reqwest::Response,
    mut on_line: impl FnMut(&str) -> Progress + Send,
) -> Result<(), LlmError> {
    let mut buf = String::new();
    let mut stream = response.bytes_stream();
    let mut deadline = tokio::time::Instant::now() + STREAM_IDLE;
    loop {
        let chunk = match tokio::time::timeout_at(deadline, stream.next()).await {
            Ok(Some(chunk)) => chunk.map_err(LlmError::transport)?,
            Ok(None) => return Ok(()),
            Err(_) => return Err(LlmError::stalled(STREAM_IDLE)),
        };
        buf.push_str(&String::from_utf8_lossy(&chunk));
        while let Some(pos) = buf.find('\n') {
            let line = buf[..pos].trim_end_matches('\r').to_string();
            buf.drain(..=pos);
            if on_line(&line) == Progress::Made {
                deadline = tokio::time::Instant::now() + STREAM_IDLE;
            }
        }
    }
}
