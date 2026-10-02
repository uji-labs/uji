use std::error::Error;
use std::time::{Duration, Instant};

use serde_json::Value;
use uji_tests::probe;

const PROCESS: &str = r#"
local process = require("uji.core.system.process")

local function ignore() end

local function outcome(result)
    if result.timed_out then
        return { "timed_out" }
    end
    return { "code", result.code }
end
"#;

#[derive(Debug)]
enum Exit {
    Code(i64),
    TimedOut,
    Cancelled,
    Unknown,
}

fn exit(value: &Value) -> Exit {
    match value[0].as_str() {
        Some("code") => Exit::Code(value[1].as_i64().unwrap_or(-1)),
        Some("timed_out") => Exit::TimedOut,
        Some("cancelled") => Exit::Cancelled,
        _ => Exit::Unknown,
    }
}

fn run(lua: &str) -> Result<Vec<Value>, Box<dyn Error>> {
    probe(&format!("{PROCESS}\n{lua}"))
}

fn strings(value: &Value) -> Vec<&str> {
    value
        .as_array()
        .map(|items| items.iter().filter_map(Value::as_str).collect())
        .unwrap_or_default()
}

#[test]
fn both_streams_and_the_exit_code_come_back() {
    let seen = run(r#"
        local out, err = {}, {}
        local result = process.run({ shell = "echo one; echo two 1>&2; exit 7" }, function(stream, line)
            if stream == "stdout" then
                out[#out + 1] = line
            else
                err[#err + 1] = line
            end
        end)
        emit(outcome(result), uji.json.array(out), uji.json.array(err))
    "#)
    .unwrap();
    let exit = exit(&seen[0]);
    let out = strings(&seen[1]);
    let err = strings(&seen[2]);
    assert!(matches!(exit, Exit::Code(7)));
    assert_eq!(out, ["one"]);
    assert_eq!(err, ["two"]);
}

#[test]
fn the_end_of_a_long_output_is_what_survives() {
    let seen = run(r#"
        local capture = process.Capture(40)
        process.run({ shell = "for i in $(seq 1 100); do echo line-$i; done" }, function(_, line)
            capture:push(line)
        end)
        emit(capture:finish())
    "#)
    .unwrap();
    let text = seen[0].as_str().unwrap_or_default();
    assert!(text.ends_with("line-100"), "{text}");
    assert!(
        !text.contains("line-1\n"),
        "kept the start instead of the end"
    );
    assert!(text.contains("earlier lines dropped"), "{text}");
}

#[test]
fn a_spill_keeps_what_the_window_drops() {
    let path = std::env::temp_dir().join("uji-capture-spill.log");
    let seen = run(&format!(
        r#"
        local capture = process.Capture(40, {:?})
        process.run({{ shell = "for i in $(seq 1 100); do echo line-$i; done" }}, function(_, line)
            capture:push(line)
        end)
        emit(capture:finish())
    "#,
        path.display().to_string()
    ))
    .unwrap();
    let text = seen[0].as_str().unwrap_or_default();
    assert!(text.contains(&path.display().to_string()), "{text}");
    let spilled = std::fs::read_to_string(&path).unwrap();
    assert_eq!(spilled.lines().count(), 100);
    assert!(spilled.starts_with("line-1\n"));
    assert!(spilled.trim_end().ends_with("line-100"));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_timeout_kills_the_command() {
    let started = Instant::now();
    let seen = run(r#"
        emit(outcome(process.run({ shell = "sleep 30", timeout = 0.2 }, ignore)))
    "#)
    .unwrap();
    let exit = exit(&seen[0]);
    assert!(matches!(exit, Exit::TimedOut));
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[test]
fn cancelling_kills_the_command() {
    let started = Instant::now();
    let seen = run(r#"
        local pid
        local worker = uji.task.spawn(function()
            local proc = process.spawn({ shell = "sleep 30" })
            pid = proc.pid
            proc:wait()
        end)
        uji.sleep(0.1)
        worker:cancel()
        uji.sleep(0.2)
        local alive = process.run({ argv = { "kill", "-0", tostring(pid) } }, ignore)
        emit(alive.code ~= 0 and { "cancelled" } or outcome(alive))
    "#)
    .unwrap();
    let exit = exit(&seen[0]);
    assert!(matches!(exit, Exit::Cancelled));
    assert!(started.elapsed() < Duration::from_secs(5));
}

#[test]
fn a_command_that_reads_with_no_writer_sees_the_end_of_input() {
    let seen = run(r#"
        emit(outcome(process.run({ shell = "cat" }, ignore)))
    "#)
    .unwrap();
    let exit = exit(&seen[0]);
    assert!(matches!(exit, Exit::Code(0)));
}

#[test]
fn what_is_written_reaches_the_command() {
    let seen = run(r#"
        local proc = process.spawn({ argv = { "cat" }, stdin = true })
        proc:write("fed\n")
        proc:close()
        local lines = {}
        for line in proc:lines() do
            lines[#lines + 1] = line
        end
        local status = proc:wait()
        emit({ "code", status.code }, uji.json.array(lines))
    "#)
    .unwrap();
    let exit = exit(&seen[0]);
    let lines = strings(&seen[1]);
    assert!(matches!(exit, Exit::Code(0)));
    assert_eq!(lines, ["fed"]);
}

#[test]
fn a_program_that_is_not_there_is_an_error_not_an_exit_code() {
    let seen = run(r#"
        emit(process.run({ argv = { "definitely-not-a-program" } }, ignore) == nil)
        emit(process.run({ argv = {} }, ignore) == nil)
    "#)
    .unwrap();
    assert!(seen[0] == true);
    assert!(seen[1] == true);
}
