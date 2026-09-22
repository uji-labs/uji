use uji_agent::llm::context::build;
use uji_agent::session::id::{MessageId, now_millis};
use uji_agent::session::model::{Message, StoredMessage, ToolCall};

fn stored(seq: i64, message: Message) -> StoredMessage {
    StoredMessage {
        id: MessageId::new(),
        seq,
        time_created: now_millis(),
        message,
    }
}

#[test]
fn a_shell_message_never_reaches_the_model() {
    let context = build(&[
        stored(
            0,
            Message::User {
                text: String::from("hello"),
            },
        ),
        stored(
            1,
            Message::Shell {
                command: String::from("cat secrets.env"),
                output: String::from("TOKEN=hunter2"),
                code: 0,
            },
        ),
    ]);
    assert_eq!(context.len(), 1);
    assert!(
        !context
            .iter()
            .any(|message| message.text().contains("hunter2")),
        "shell output leaked into the context"
    );
}

#[test]
fn a_tool_call_without_its_result_is_dropped() {
    let context = build(&[stored(
        0,
        Message::Assistant {
            text: String::from("looking"),
            tool_calls: vec![ToolCall {
                id: String::from("call-1"),
                name: String::from("read_file"),
                arguments: String::from("{}"),
            }],
            reasoning_content: None,
        },
    )]);
    assert!(matches!(
        context.as_slice(),
        [Message::Assistant { text, tool_calls, .. }]
            if text == "looking" && tool_calls.is_empty()
    ));
}

#[test]
fn a_compaction_cuts_the_history_it_summarised() {
    let context = build(&[
        stored(
            0,
            Message::User {
                text: String::from("ancient history"),
            },
        ),
        stored(
            1,
            Message::Compaction {
                summary: String::from("they said hello"),
                through: 0,
                files: vec![String::from("src/main.rs")],
            },
        ),
        stored(
            2,
            Message::User {
                text: String::from("recent"),
            },
        ),
    ]);
    assert_eq!(context.len(), 2);
    assert!(context[0].text().contains("they said hello"));
    assert!(!context[0].text().contains("ancient history"));
    assert_eq!(context[1].text(), "recent");
}
