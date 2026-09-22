use std::time::Duration;

use futures_util::StreamExt as _;

use super::LlmError;

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

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Progress {
    Made,
    Keepalive,
}

impl From<bool> for Progress {
    fn from(moved: bool) -> Self {
        if moved { Self::Made } else { Self::Keepalive }
    }
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
