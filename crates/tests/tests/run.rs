use std::error::Error;
use std::io;
use std::process::{Command, Output};

use serde_json::{Value, json};
use uji_tests::{Reply, Request, Sandbox, Server, provider, text, tool_calls};

const MODEL: &str = r#"
require("uji.core.model").set_setting("llm.provider", "test")
require("uji.core.model").set_setting("llm.model", "m")
"#;

fn sandbox(server: &Server) -> Result<Sandbox, Box<dyn Error>> {
    let sandbox = Sandbox::new("run")?;
    sandbox.file("notes.txt", "alpha\nline two\ngamma\n")?;
    sandbox.config(&format!("{}\n{MODEL}", provider(&server.url, 100_000)))?;
    Ok(sandbox)
}

fn uji(sandbox: &Sandbox, args: &[&str]) -> Result<Output, Box<dyn Error>> {
    let root = sandbox.root();
    Ok(Command::new(env!("CARGO_BIN_EXE_uji-test"))
        .arg("run")
        .arg("--config-dir")
        .arg(root.join("cfg"))
        .arg("--data-dir")
        .arg(root.join("data"))
        .arg("--db")
        .arg(root.join("uji.db"))
        .args(args)
        .current_dir(sandbox.work())
        .output()?)
}

fn events(output: &Output) -> Vec<Value> {
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

fn kinds(events: &[Value]) -> Vec<String> {
    events
        .iter()
        .map(|event| match event["type"].as_str().unwrap_or_default() {
            "message" => format!(
                "message:{}",
                event["message"]["type"].as_str().unwrap_or_default()
            ),
            other => other.to_string(),
        })
        .collect()
}

fn tool_contents(events: &[Value]) -> Vec<String> {
    events
        .iter()
        .filter(|event| event["message"]["type"] == "tool")
        .filter_map(|event| event["message"]["content"].as_str().map(String::from))
        .collect()
}

fn answered(request: &Request) -> bool {
    request.body["messages"]
        .as_array()
        .is_some_and(|messages| messages.iter().any(|message| message["role"] == "tool"))
}

fn after(calls: &'static [(&'static str, &'static str)]) -> io::Result<Server> {
    Server::start(move |request: &Request| {
        if answered(request) {
            text("finished")
        } else {
            tool_calls(0, calls)
        }
    })
}

#[test]
fn run_prints_the_answer_and_exits() {
    let server = Server::start(|_: &Request| text("hello there")).unwrap();
    let sandbox = sandbox(&server).unwrap();
    let output = uji(&sandbox, &["say", "hi"]).unwrap();
    assert!(output.status.success());
    assert_eq!(String::from_utf8_lossy(&output.stdout), "hello there\n");
    let sent = &server.turns()[0];
    assert_eq!(sent.body["messages"][1]["content"], "say hi");
}

#[test]
fn run_json_prints_each_message_and_ends_with_done() {
    let server = after(&[("read_file", r#"{"path":"notes.txt"}"#)]).unwrap();
    let sandbox = sandbox(&server).unwrap();
    let output = uji(&sandbox, &["--json", "read the notes"]).unwrap();
    assert!(output.status.success());
    let seen = events(&output);
    assert_eq!(
        kinds(&seen),
        [
            "session",
            "message:user",
            "message:assistant",
            "message:tool",
            "message:assistant",
            "done"
        ]
    );
    assert!(tool_contents(&seen)[0].contains("line two"));
    let done = seen.last().unwrap();
    assert_eq!(done["text"], "finished");
    assert!(done["usage"]["input"].as_u64().unwrap() > 0);
}

#[test]
fn run_takes_its_model_tools_and_prompt_from_flags() {
    let server = Server::start(|_: &Request| text("ok")).unwrap();
    let sandbox = sandbox(&server).unwrap();
    let output = uji(
        &sandbox,
        &[
            "--model",
            "test/m2",
            "--tools",
            "read_file",
            "--append-prompt",
            "You check files.",
            "check",
        ],
    )
    .unwrap();
    assert!(output.status.success());
    let sent = &server.turns()[0];
    assert_eq!(sent.body["model"], "m2");
    let tools: Vec<&str> = sent.body["tools"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|tool| tool["function"]["name"].as_str())
        .collect();
    assert_eq!(tools, ["read_file"]);
    assert!(sent.system().ends_with("\n\nYou check files."));
}

#[test]
fn run_allows_what_would_ask_and_keeps_denials() {
    let calls: &[(&str, &str)] = &[("run_command", r#"{"command":"echo hi"}"#)];
    let server = after(calls).unwrap();
    let sandbox = sandbox(&server).unwrap();
    let allowed = events(&uji(&sandbox, &["--json", "say hi"]).unwrap());
    assert!(tool_contents(&allowed)[0].contains("hi"));
    let deny = r#"uji.tool.policy({ run_command = { deny = { "echo *" } } })"#;
    sandbox
        .config(&format!(
            "{}\n{MODEL}\n{deny}",
            provider(&server.url, 100_000)
        ))
        .unwrap();
    let denied = events(&uji(&sandbox, &["--json", "say hi"]).unwrap());
    assert_eq!(tool_contents(&denied), ["denied: denied by policy"]);
}

#[test]
fn run_saves_its_session_under_a_parent() {
    let server = Server::start(|_: &Request| text("ok")).unwrap();
    let sandbox = sandbox(&server).unwrap();
    let first = events(&uji(&sandbox, &["--json", "start"]).unwrap());
    let parent = first[0]["id"].as_str().unwrap().to_string();
    let child = uji(
        &sandbox,
        &["--parent", &parent, "--title", "find the parser", "look"],
    )
    .unwrap();
    assert!(child.status.success());
    let missing = uji(
        &sandbox,
        &["--parent", "00000000-0000-0000-0000-000000000000", "look"],
    )
    .unwrap();
    assert_eq!(missing.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&missing.stderr).contains("no session with id"));
    let seen = sandbox
        .probe(
            r#"
            local rows = require("uji.core.app").store.db:query("SELECT title, parent FROM sessions WHERE parent IS NOT NULL")
            for _, row in ipairs(rows) do
                emit(row.title, row.parent)
            end
            "#,
        )
        .unwrap();
    assert_eq!(seen, [json!("find the parser"), json!(parent)]);
}

#[test]
fn run_reports_a_failed_turn_and_exits_with_one() {
    let server = Server::start(|_: &Request| Reply::Status {
        code: 400,
        headers: Vec::new(),
        body: String::from(r#"{"error":{"message":"bad request"}}"#),
    })
    .unwrap();
    let sandbox = sandbox(&server).unwrap();
    let output = uji(&sandbox, &["--json", "hello"]).unwrap();
    assert_eq!(output.status.code(), Some(1));
    let done = events(&output).last().cloned().unwrap();
    assert_eq!(done["type"], "done");
    assert!(done["error"].as_str().unwrap().contains("bad request"));
    let plain = uji(&sandbox, &["hello"]).unwrap();
    assert_eq!(plain.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&plain.stderr).starts_with("uji: error:"));
}

#[test]
fn uji_knows_its_program_and_arguments() {
    let seen = uji_tests::probe("emit(type(uji.os.executable), uji.os.argv[2])").unwrap();
    assert_eq!(seen, [json!("string"), json!("new")]);
}
