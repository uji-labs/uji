use crate::llm::{Llm, LlmError, LlmRequest};
use crate::session::model::Message;

pub struct Echo;

impl Llm for Echo {
    fn id(&self) -> &'static str {
        "echo"
    }

    fn send_request(&self, request: &LlmRequest) -> Result<String, LlmError> {
        let last = request
            .messages
            .iter()
            .rev()
            .find_map(|message| match message {
                Message::User { text } => Some(text.as_str()),
                _ => None,
            })
            .unwrap_or("nothing");
        Ok(format!("echo: {last}"))
    }
}
