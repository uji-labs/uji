use uji_core::llm::context::build;
use uji_core::session::id::{MessageId, now_millis};
use uji_core::session::model::{Message, StoredMessage};

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
    let history = [
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
    ];
    let context = build(&history);
    assert_eq!(context.len(), 1);
    assert!(
        !context
            .iter()
            .any(|message| message.text().contains("hunter2")),
        "shell output leaked into the context"
    );
}

#[test]
fn a_compaction_cuts_the_history_it_summarised() {
    let history = [
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
    ];
    let context = build(&history);
    assert_eq!(context.len(), 2);
    assert!(context[0].text().contains("they said hello"));
    assert!(!context[0].text().contains("ancient history"));
    assert_eq!(context[1].text(), "recent");
}
