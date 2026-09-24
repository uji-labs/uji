use uji_core::session::id::{MessageId, now_millis};
use uji_core::session::model::{Message, Stamp, StoredMessage, ToolCall};

use super::LoopData;
use crate::runtime::events;

const STOPPED: &str = "error: uji stopped before this tool returned a result";

impl LoopData {
    pub(super) fn append(&mut self, message: Message) {
        let id = self.app.messages().info().id;
        let stamp = match self.storage.append_message(&id, &message) {
            Ok(stamp) => stamp,
            Err(err) => {
                self.inner.notify(format!(
                    "failed to persist {} message: {err}",
                    message.type_name()
                ));
                self.unsaved_stamp()
            }
        };
        let kind = message.type_name();
        let text = message.text().to_string();
        self.app
            .conversation()
            .borrow_mut()
            .push(StoredMessage::new(stamp, message));
        self.inner
            .emit(&events::MessageAppended { kind, text: &text });
        self.dirty = true;
    }

    pub(super) fn answer_unanswered_calls(&mut self) {
        let results: Vec<Message> = self
            .app
            .messages()
            .unanswered_calls()
            .into_iter()
            .map(|call| Message::Tool {
                tool_call_id: call.id.clone(),
                name: call.name.clone(),
                content: STOPPED.to_string(),
            })
            .collect();
        for result in results {
            self.append(result);
        }
    }

    fn unsaved_stamp(&self) -> Stamp {
        let seq = self
            .app
            .messages()
            .messages()
            .last()
            .map_or(0, |last| last.seq)
            .saturating_add(1);
        Stamp {
            id: MessageId::new(),
            seq,
            time_created: now_millis(),
        }
    }

    pub(super) fn persist_assistant_step(
        &mut self,
        text: String,
        tool_calls: Vec<ToolCall>,
        reasoning: Option<String>,
    ) {
        self.append(Message::Assistant {
            text,
            tool_calls,
            reasoning,
        });
    }

    pub(super) fn persist_tool_result(
        &mut self,
        tool_call_id: String,
        name: String,
        content: String,
    ) {
        self.append(Message::Tool {
            tool_call_id,
            name,
            content,
        });
    }
    pub(super) fn fail_assistant(&mut self, error: &str) {
        self.append(Message::Error {
            text: error.to_string(),
        });
    }

    pub(super) fn finish_assistant(&mut self, text: &str, reasoning: Option<String>) {
        self.app.take_pending();
        self.append(Message::Assistant {
            text: text.to_string(),
            tool_calls: Vec::new(),
            reasoning,
        });
    }
}
