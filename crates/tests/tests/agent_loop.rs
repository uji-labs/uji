use std::error::Error;
use std::io;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use serde_json::json;
use uji_tests::{
    ALLOW_ALL, Message, Reply, Request, SUBMIT, Sandbox, Server, Until, events, provider, text,
    tool_calls, tool_results,
};

type Ran = Result<Vec<Message>, Box<dyn Error>>;

fn serve(script: impl Fn(usize) -> Reply + Send + Sync + 'static) -> io::Result<Server> {
    let round = AtomicUsize::new(0);
    Server::start(move |request: &Request| {
        if !request.has_tools() {
            let answer = if request.system().contains("compact") {
                "SUMMARY OF EARLIER WORK"
            } else {
                "Title"
            };
            return text(answer);
        }
        script(round.fetch_add(1, Ordering::SeqCst))
    })
}

fn run(server: &Server, context: u64, lua: &str, answers: &[char], secs: u64) -> Ran {
    let sandbox = Sandbox::new("loop")?;
    sandbox.file("notes.txt", "alpha\nline two\ngamma\n")?;
    sandbox.config(&format!(
        "{}\n{lua}\n{SUBMIT}",
        provider(&server.url, context)
    ))?;
    sandbox.run(Until::TurnFinished, answers, Duration::from_secs(secs))
}

fn read_notes() -> Reply {
    tool_calls(0, &[("read_file", r#"{"path":"notes.txt"}"#)])
}

fn last_error(messages: &[Message]) -> Option<&str> {
    match messages.last() {
        Some(Message::Error { text }) => Some(text),
        _ => None,
    }
}

fn last_answer(messages: &[Message]) -> Option<&str> {
    match messages.last() {
        Some(Message::Assistant {
            text, tool_calls, ..
        }) if tool_calls.is_empty() => Some(text),
        _ => None,
    }
}

#[test]
fn a_failed_request_is_retried_until_it_succeeds() {
    let server = serve(|round| match round {
        0 => Reply::Status {
            code: 500,
            headers: Vec::new(),
            body: String::from("boom"),
        },
        1 => Reply::Status {
            code: 429,
            headers: vec![("retry-after", String::from("1"))],
            body: String::from(r#"{"error":"slow"}"#),
        },
        2 => read_notes(),
        _ => text("done"),
    })
    .unwrap();
    let messages = run(&server, 100_000, ALLOW_ALL, &[], 30).unwrap();
    assert_eq!(server.turns().len(), 4);
    assert_eq!(
        tool_results(&messages),
        ["    1| alpha\n    2| line two\n    3| gamma\n"]
    );
    assert_eq!(last_answer(&messages), Some("done"));
}

#[test]
fn malformed_arguments_and_unknown_tools_are_answered_without_running() {
    let server = serve(|round| match round {
        0 => tool_calls(
            0,
            &[
                ("read_file", "[1,2]"),
                ("read_file", "null"),
                ("read_file", r#""s""#),
                ("read_file", ""),
                ("read_file", " 7 "),
                ("nope", "{}"),
            ],
        ),
        _ => text("ok"),
    })
    .unwrap();
    let messages = run(&server, 100_000, ALLOW_ALL, &[], 10).unwrap();
    let shape = |kind: &str| {
        format!(
            "error: arguments must be a JSON object, got {kind}. Send a single object matching the tool schema."
        )
    };
    assert_eq!(
        tool_results(&messages),
        [
            shape("an array"),
            shape("null"),
            shape("a string"),
            String::from("error: `path` is required and must be a non-empty string"),
            shape("a number"),
            String::from(
                "error: unknown tool `nope`. Available tools: edit_file, read_file, run_command, write_file."
            ),
        ]
    );
}

#[test]
fn a_message_sent_during_a_turn_steers_it() {
    let server = serve(|round| match round {
        0 => tool_calls(0, &[("run_command", r#"{"command":"sleep 1"}"#)]),
        _ => text("done"),
    })
    .unwrap();
    let steer = r#"uji.on("tool_started", function() uji.session.submit("extra") end)"#;
    let messages = run(&server, 100_000, &format!("{ALLOW_ALL}\n{steer}"), &[], 15).unwrap();
    let turns = server.turns();
    assert_eq!(turns.len(), 2);
    let sent = &turns[1].body["messages"];
    let last = &sent[sent.as_array().unwrap().len() - 1];
    assert_eq!(last["role"], "user");
    assert_eq!(last["content"], "extra");
    assert!(
        messages
            .iter()
            .any(|message| matches!(message, Message::User { text } if text == "extra"))
    );
    assert_eq!(last_answer(&messages), Some("done"));
}

#[test]
fn approval_keys_allow_one_call_and_deny_the_next() {
    let server = serve(|round| match round {
        0 => tool_calls(
            0,
            &[
                (
                    "edit_file",
                    r#"{"path":"notes.txt","old_string":"alpha","new_string":"ALPHA"}"#,
                ),
                ("write_file", r#"{"path":"x.txt","content":"x"}"#),
            ],
        ),
        _ => text("done"),
    })
    .unwrap();
    let messages = run(&server, 100_000, "", &['y', 'n'], 15).unwrap();
    assert_eq!(
        tool_results(&messages),
        ["edited notes.txt at line 1", "denied: user denied"]
    );
    assert_eq!(last_answer(&messages), Some("done"));
}

#[test]
fn a_turn_that_outgrows_its_window_is_compacted_mid_turn() {
    let server = serve(|round| match round {
        0 => tool_calls(0, &[("run_command", r#"{"command":"seq 1 4000"}"#)]),
        _ => text("done"),
    })
    .unwrap();
    let messages = run(&server, 4_000, ALLOW_ALL, &[], 20).unwrap();
    assert!(
        server
            .requests()
            .iter()
            .any(|request| request.system().starts_with("You compact coding sessions"))
    );
    let turns = server.turns();
    assert_eq!(turns.len(), 2);
    let folded = turns[1].body["messages"][1]["content"].as_str().unwrap();
    assert!(folded.starts_with("Summary of the earlier part of this conversation:"));
    assert!(folded.contains("SUMMARY OF EARLIER WORK"));
    assert_eq!(last_answer(&messages), Some("done"));
}

#[test]
fn a_turn_keeps_calling_tools_until_the_model_answers() {
    let server = serve(|round| {
        if round < 150 {
            read_notes()
        } else {
            text("done")
        }
    })
    .unwrap();
    let messages = run(&server, 100_000, ALLOW_ALL, &[], 90).unwrap();
    assert_eq!(server.turns().len(), 151);
    assert_eq!(last_answer(&messages), Some("done"));
}

#[test]
fn a_tool_call_without_an_id_is_given_one() {
    let server = serve(|round| match round {
        0 => events(&[
            json!({"choices": [{"index": 0, "delta": {"tool_calls": [
                {"index": 0, "type": "function", "function": {"name": "read_file", "arguments": r#"{"path":"notes.txt"}"#}}
            ]}, "finish_reason": null}]}),
            json!({"choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]}),
        ]),
        _ => text("done"),
    }).unwrap();
    let messages = run(&server, 100_000, ALLOW_ALL, &[], 10).unwrap();
    let called = messages.iter().find_map(|message| match message {
        Message::Assistant { tool_calls, .. } => tool_calls.first().map(|call| call.id.clone()),
        _ => None,
    });
    let answered = messages.iter().find_map(|message| match message {
        Message::Tool { tool_call_id, .. } => Some(tool_call_id.clone()),
        _ => None,
    });
    let id = called.unwrap();
    assert!(id.starts_with("call_") && id.len() > "call_".len());
    assert_eq!(answered, Some(id));
}

#[test]
fn interrupting_a_running_tool_ends_the_turn() {
    let server = serve(|round| match round {
        0 => tool_calls(0, &[("run_command", r#"{"command":"sleep 30"}"#)]),
        _ => text("done"),
    })
    .unwrap();
    let interrupt =
        r#"uji.on("tool_started", function() uji.defer(0.5, uji.session.interrupt) end)"#;
    let started = Instant::now();
    let messages = run(
        &server,
        100_000,
        &format!("{ALLOW_ALL}\n{interrupt}"),
        &[],
        20,
    )
    .unwrap();
    assert!(started.elapsed() < Duration::from_secs(10));
    assert_eq!(
        tool_results(&messages),
        ["error: interrupted by the user while this tool ran"]
    );
    assert_eq!(last_error(&messages), Some("interrupted"));
    assert_eq!(server.turns().len(), 1);
}

#[test]
fn interrupting_a_stream_drops_the_connection() {
    let server = serve(|_| Reply::Drip {
        line: String::from(r#"data: {"choices":[{"index":0,"delta":{"content":"."}}]}"#),
        every: Duration::from_millis(200),
    })
    .unwrap();
    let messages = run(
        &server,
        100_000,
        "uji.defer(1, uji.session.interrupt)",
        &[],
        20,
    )
    .unwrap();
    assert_eq!(last_error(&messages), Some("interrupted"));
    let waited = Instant::now();
    while server.dropped() == 0 && waited.elapsed() < Duration::from_secs(3) {
        std::thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(server.dropped(), 1);
}

#[test]
fn a_stream_that_only_sends_keepalives_is_given_up_and_retried() {
    let server = serve(|_| Reply::Drip {
        line: String::from(r#"data: {"choices":[{"index":0,"delta":{}}]}"#),
        every: Duration::from_millis(200),
    })
    .unwrap();
    run(&server, 100_000, "uji.api.stream.idle = 1", &[], 6).unwrap();
    assert!(server.turns().len() >= 2);
}

#[test]
fn a_message_that_waits_for_compaction_is_sent_once_it_is_done() {
    let server = serve(|_| text("done")).unwrap();
    let sandbox = Sandbox::new("loop").unwrap();
    for turn in 0..6 {
        sandbox.remember(Message::User {
            text: format!("question {turn}"),
        });
        sandbox.remember(Message::Assistant {
            text: "answer ".repeat(400),
            tool_calls: Vec::new(),
            reasoning: None,
        });
    }
    sandbox
        .config(&format!("{}\n{SUBMIT}", provider(&server.url, 4_000)))
        .unwrap();
    let messages = sandbox
        .run(Until::TurnFinished, &[], Duration::from_secs(20))
        .unwrap();
    assert!(
        server
            .requests()
            .iter()
            .any(|request| request.system().starts_with("You compact coding sessions"))
    );
    let turns = server.turns();
    assert_eq!(turns.len(), 1);
    let sent = &turns[0].body["messages"];
    let last = &sent[sent.as_array().unwrap().len() - 1];
    assert_eq!(last["content"], "go");
    assert_eq!(last_answer(&messages), Some("done"));
}

#[test]
fn a_plugin_can_answer_approval_questions() {
    let echo = || {
        serve(|round| match round {
            0 => tool_calls(0, &[("run_command", r#"{"command":"echo hi"}"#)]),
            _ => text("done"),
        })
        .unwrap()
    };
    let answer = |allow: bool| {
        format!(
            r#"uji.ui.confirm = function(request)
                return request.body:find("echo hi", 1, true) ~= nil and {allow}
            end"#
        )
    };
    let server = echo();
    let allowed = run(&server, 100_000, &answer(true), &[], 10).unwrap();
    assert!(tool_results(&allowed)[0].contains("hi"));
    let server = echo();
    let denied = run(&server, 100_000, &answer(false), &[], 10).unwrap();
    assert_eq!(tool_results(&denied), ["denied: user denied"]);
}
