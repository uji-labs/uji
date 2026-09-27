use std::error::Error;

use serde::Serialize;
use uji_tests::{Message, probe};

#[derive(Serialize)]
struct StoredMessage {
    seq: i64,
    message: Message,
}

fn stored(seq: i64, message: Message) -> StoredMessage {
    StoredMessage { seq, message }
}

fn build(history: &[StoredMessage]) -> Result<Vec<Message>, Box<dyn Error>> {
    let history = serde_json::to_string(history)?;
    let seen = probe(&format!(
        r#"
        local view = require("uji.agent.view")
        local stored = uji.json.decode({history:?}, {{ nulls = false }})
        for _, message in ipairs(view.build(stored)) do
            emit(message)
        end
    "#
    ))?;
    Ok(seen
        .into_iter()
        .map(serde_json::from_value)
        .collect::<Result<_, _>>()?)
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
    let context = build(&history).unwrap();
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
    let context = build(&history).unwrap();
    assert_eq!(context.len(), 2);
    assert!(context[0].text().contains("they said hello"));
    assert!(!context[0].text().contains("ancient history"));
    assert_eq!(context[1].text(), "recent");
}
