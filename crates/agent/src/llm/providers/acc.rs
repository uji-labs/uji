use crate::llm::error::LlmError;
use crate::session::model::ToolCall;

pub struct Partial {
    index: usize,
    pub id: String,
    pub name: String,
    pub arguments: String,
}

impl Partial {
    fn new(index: usize) -> Self {
        Self {
            index,
            id: String::new(),
            name: String::new(),
            arguments: String::new(),
        }
    }
}

#[derive(Default)]
pub struct ToolAcc {
    calls: Vec<Partial>,
}

impl ToolAcc {
    pub fn entry(&mut self, index: usize) -> &mut Partial {
        let position = self
            .calls
            .iter()
            .position(|call| call.index == index)
            .unwrap_or(self.calls.len());
        if position == self.calls.len() {
            self.calls.push(Partial::new(index));
        }
        &mut self.calls[position]
    }

    pub fn finish(self) -> Result<Vec<ToolCall>, LlmError> {
        let mut calls = self.calls;
        calls.sort_by_key(|call| call.index);
        if let Some(cut) = calls.iter().find(|call| incomplete(&call.arguments)) {
            return Err(LlmError::truncated_call(&cut.name));
        }
        Ok(calls
            .into_iter()
            .map(|call| ToolCall {
                id: call.id,
                name: call.name,
                arguments: call.arguments,
            })
            .collect())
    }
}

/// Whether a call's arguments stop short of being JSON.
fn incomplete(arguments: &str) -> bool {
    let arguments = arguments.trim();
    !arguments.is_empty() && serde_json::from_str::<serde_json::Value>(arguments).is_err()
}

/// The arguments of a stored tool call, as an object fit for the wire.
///
/// A reply cut off mid-call leaves half-written JSON in the transcript. It
/// cannot be repaired into what the model meant, but it must not be sent back
/// as-is: providers reject the whole request, so one truncated call would
/// otherwise wedge the session for good.
pub fn arguments_of(raw: &str) -> serde_json::Value {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return serde_json::Value::Object(serde_json::Map::new());
    }
    match serde_json::from_str(trimmed) {
        Ok(value @ serde_json::Value::Object(_)) => value,
        _ => serde_json::Value::Object(serde_json::Map::new()),
    }
}
