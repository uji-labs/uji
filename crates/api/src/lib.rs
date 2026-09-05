pub mod buffer;
pub mod llm;
pub mod opts;
pub mod window;

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("unknown buffer kind: {0}")]
    UnknownBufferKind(String),
}
