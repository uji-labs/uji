use std::time::{Duration, Instant};

use uji_agent::llm::CancelToken;
use uji_agent::process::{self, Capture, Exit, Spec, Stream};

#[tokio::test]
async fn both_streams_and_the_exit_code_come_back() {
    let cancel = CancelToken::new();
    let mut out = Vec::new();
    let mut err = Vec::new();
    let exit = process::stream(
        Spec::shell("echo one; echo two 1>&2; exit 7"),
        &cancel,
        |stream, line| match stream {
            Stream::Out => out.push(line),
            Stream::Err => err.push(line),
        },
    )
    .await
    .unwrap();
    assert!(matches!(exit, Exit::Code(7)));
    assert_eq!(out, ["one"]);
    assert_eq!(err, ["two"]);
}

#[tokio::test]
async fn the_end_of_a_long_output_is_what_survives() {
    let cancel = CancelToken::new();
    let mut capture = Capture::new(40);
    process::stream(
        Spec::shell("for i in $(seq 1 100); do echo line-$i; done"),
        &cancel,
        |_, line| capture.push(&line),
    )
    .await
    .unwrap();
    let text = capture.finish();
    assert!(text.ends_with("line-100"), "{text}");
    assert!(
        !text.contains("line-1\n"),
        "kept the start instead of the end"
    );
    assert!(text.contains("earlier lines dropped"), "{text}");
}

#[tokio::test]
async fn a_spill_keeps_what_the_window_drops() {
    let cancel = CancelToken::new();
    let path = std::env::temp_dir().join("uji-capture-spill.log");
    let mut capture = Capture::new(40).spilling(path.clone());
    process::stream(
        Spec::shell("for i in $(seq 1 100); do echo line-$i; done"),
        &cancel,
        |_, line| capture.push(&line),
    )
    .await
    .unwrap();
    let text = capture.finish();
    assert!(text.contains(&path.display().to_string()), "{text}");
    let spilled = std::fs::read_to_string(&path).unwrap();
    assert_eq!(spilled.lines().count(), 100);
    assert!(spilled.starts_with("line-1\n"));
    assert!(spilled.trim_end().ends_with("line-100"));
    let _ = std::fs::remove_file(&path);
}

#[tokio::test]
async fn a_timeout_kills_the_command() {
    let cancel = CancelToken::new();
    let started = Instant::now();
    let exit = process::stream(
        Spec::shell("sleep 30").within(Duration::from_millis(200)),
        &cancel,
        |_, _| {},
    )
    .await
    .unwrap();
    assert!(matches!(exit, Exit::TimedOut));
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[tokio::test]
async fn cancelling_kills_the_command() {
    let cancel = CancelToken::new();
    let stopper = cancel.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(100)).await;
        stopper.cancel();
    });
    let started = Instant::now();
    let exit = process::stream(Spec::shell("sleep 30"), &cancel, |_, _| {})
        .await
        .unwrap();
    assert!(matches!(exit, Exit::Cancelled));
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[tokio::test]
async fn a_command_that_reads_with_no_writer_sees_the_end_of_input() {
    let cancel = CancelToken::new();
    let exit = process::stream(Spec::shell("cat"), &cancel, |_, _| {})
        .await
        .unwrap();
    assert!(matches!(exit, Exit::Code(0)));
}

#[tokio::test]
async fn what_is_written_reaches_the_command() {
    let cancel = CancelToken::new();
    let (writes, reader) = tokio::sync::mpsc::unbounded_channel();
    writes.send(Some(String::from("fed\n"))).unwrap();
    writes.send(None).unwrap();
    let argv = vec![String::from("cat")];
    let mut lines = Vec::new();
    let exit = process::stream(Spec::argv(&argv).writing(reader), &cancel, |_, line| {
        lines.push(line);
    })
    .await
    .unwrap();
    assert!(matches!(exit, Exit::Code(0)));
    assert_eq!(lines, ["fed"]);
}

#[tokio::test]
async fn a_program_that_is_not_there_is_an_error_not_an_exit_code() {
    let cancel = CancelToken::new();
    let missing = vec![String::from("definitely-not-a-program")];
    assert!(
        process::stream(Spec::argv(&missing), &cancel, |_, _| {})
            .await
            .is_err()
    );
    let empty: Vec<String> = Vec::new();
    assert!(
        process::stream(Spec::argv(&empty), &cancel, |_, _| {})
            .await
            .is_err()
    );
}
