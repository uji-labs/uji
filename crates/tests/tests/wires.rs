use std::collections::BTreeMap;
use std::time::Duration;

use serde_json::{Map, Value, json};
use uji_tests::{
    Effort, Message, Reply, Request, Retention, Sandbox, Server, ToolCall, ToolSpec, Until,
};

const IDENTITY: &str = "You are Claude Code, Anthropic's official CLI for Claude.";

const HEADERS: [&str; 6] = [
    "authorization",
    "x-api-key",
    "x-goog-api-key",
    "anthropic-version",
    "anthropic-beta",
    "content-type",
];

const HARNESS: &str = r#"
local out = io.open(OUT, "w")
local cases = {}
for line in io.lines(CASES) do
    cases[#cases + 1] = uji.json.decode(line, { nulls = false })
end

local RETRYABLE = { [408] = true, [409] = true, [425] = true, [429] = true }
local WIRES = { ["openai-chat"] = "openai_chat", anthropic = "anthropic", gemini = "gemini" }

local function display(failure)
    if failure.kind == "auth" then
        return "authentication rejected (" .. failure.status .. ") - check the api key for this provider", false
    elseif failure.kind == "provider" then
        return "provider: " .. failure.message, false
    end
    local status = failure.status
    local retryable = status == nil or RETRYABLE[status] or (status >= 500 and status < 600)
    local head = status and (status .. ": ") or ""
    return "http: " .. head .. failure.message, retryable, failure.retry_after and math.min(failure.retry_after, 60)
end

local run

local function record(case, deltas, result)
    out:write(uji.json.encode({ case = case.case, result = result, deltas = deltas }), "\n")
    run(case.at + 1)
end

run = function(at)
    local case = cases[at]
    if not case then
        out:close()
        return uji.session.set_title("finished")
    end
    case.at = at
    local deltas = uji.json.array({})
    local reply = {
        text = function(text) deltas[#deltas + 1] = { "text", text } end,
        reasoning = function(text) deltas[#deltas + 1] = { "reasoning", text } end,
        done = function(answer)
            record(case, deltas, { ok = {
                text = answer.text,
                reasoning = answer.reasoning or uji.json.null,
                tool_calls = uji.json.array(answer.tool_calls),
                usage = answer.usage or uji.json.null,
            } })
        end,
        fail = function(failure)
            local message, retryable, after = display(failure)
            record(case, deltas, { err = { message = message, retryable = retryable, retry_after = after or uji.json.null } })
        end,
    }
    require("uji.wires." .. WIRES[case.wire]).stream(case.request, reply)
end

uji.schedule(function() run(1) end)
"#;

struct Case {
    wire: &'static str,
    script: &'static str,
    host: &'static str,
    compat: Value,
    oauth: bool,
    system: Option<String>,
    messages: Vec<Message>,
    tools: Vec<ToolSpec>,
    effort: Effort,
    cache: Retention,
    max_output: u32,
}

fn call(id: &str, name: &str, arguments: &str) -> ToolCall {
    ToolCall {
        id: id.into(),
        name: name.into(),
        arguments: arguments.into(),
    }
}

fn user(text: &str) -> Message {
    Message::User { text: text.into() }
}

fn histories() -> [Vec<Message>; 4] {
    [
        vec![user("hi")],
        vec![
            user("hi"),
            Message::Assistant {
                text: "hello".into(),
                tool_calls: vec![],
                reasoning: None,
            },
            user("again"),
        ],
        vec![
            user("fix"),
            Message::Assistant {
                text: String::new(),
                tool_calls: vec![
                    call("c1", "read_file", r#"{"path":"a.rs"}"#),
                    call("c2", "run_command", ""),
                    call("c3", "edit_file", r#"{"path": "x"#),
                ],
                reasoning: None,
            },
            Message::Tool {
                tool_call_id: "c1".into(),
                name: "read_file".into(),
                content: "contents".into(),
            },
            Message::Tool {
                tool_call_id: "c2".into(),
                name: "run_command".into(),
                content: "out".into(),
            },
            Message::Tool {
                tool_call_id: "c3".into(),
                name: "edit_file".into(),
                content: "error: bad".into(),
            },
            user("next"),
        ],
        vec![
            Message::System {
                text: "sys note".into(),
            },
            user("q"),
            Message::Shell {
                command: "ls".into(),
                output: "a".into(),
                code: 0,
            },
            Message::Error {
                text: "boom".into(),
            },
            Message::Compaction {
                summary: "sum".into(),
                through: 3,
                files: vec!["f".into()],
            },
            Message::Assistant {
                text: "a".into(),
                tool_calls: vec![],
                reasoning: Some("r".into()),
            },
            Message::System {
                text: "later note".into(),
            },
            user("q2"),
        ],
    ]
}

fn tools() -> Vec<ToolSpec> {
    vec![
        ToolSpec {
            name: "read_file".into(),
            description: "Read a file.".into(),
            parameters: json!({
                "type": "object",
                "properties": {"path": {"type": "string"}, "offset": {"type": "integer", "minimum": 1}},
                "required": ["path"],
                "additionalProperties": false,
            }),
        },
        ToolSpec {
            name: "noop".into(),
            description: "Nothing.".into(),
            parameters: json!({"type": "object", "properties": {}, "required": []}),
        },
    ]
}

fn base(wire: &'static str, script: &'static str) -> Case {
    Case {
        wire,
        script,
        host: "example.local",
        compat: json!({}),
        oauth: false,
        system: Some("You are a test.".into()),
        messages: histories()[0].clone(),
        tools: tools(),
        effort: Effort::Off,
        cache: Retention::Off,
        max_output: 8192,
    }
}

fn history(at: usize) -> Vec<Message> {
    histories()[at].clone()
}

fn openai_cases() -> Vec<Case> {
    let efforts = [Effort::Off, Effort::Low, Effort::High];
    let mut out = Vec::new();
    for host in [
        "api.openai.com",
        "openrouter.ai",
        "api.deepseek.com",
        "open.bigmodel.cn",
        "dashscope.aliyuncs.com",
        "example.local",
    ] {
        for effort in efforts {
            for at in [0, 2, 3] {
                out.push(Case {
                    host,
                    effort,
                    messages: history(at),
                    ..base("openai-chat", "oa-text")
                });
            }
        }
    }
    for thinking in ["openai", "openrouter", "deepseek", "zai", "qwen", "none"] {
        for field in ["max_tokens", "max_completion_tokens", "none"] {
            for name in [false, true] {
                out.push(Case {
                    compat: json!({"max_tokens_field": field, "thinking": thinking, "tool_result_name": name}),
                    effort: Effort::Medium,
                    messages: history(2),
                    ..base("openai-chat", "oa-text")
                });
            }
        }
    }
    out.push(Case {
        effort: Effort::High,
        max_output: 1000,
        ..base("openai-chat", "oa-text")
    });
    out.push(Case {
        tools: vec![],
        system: None,
        ..base("openai-chat", "oa-text")
    });
    out.push(Case {
        effort: Effort::Minimal,
        messages: history(1),
        ..base("openai-chat", "oa-text")
    });
    out.push(Case {
        compat: json!({"finish_reason": false}),
        ..base("openai-chat", "oa-unfinished")
    });
    for script in [
        "oa-think",
        "oa-tools",
        "oa-noid",
        "oa-usage",
        "oa-length",
        "oa-done-only",
        "oa-unfinished",
        "oa-empty",
        "oa-cutcall",
        "oa-garbage",
        "err-429",
        "err-401",
        "err-500",
        "err-400",
    ] {
        out.push(base("openai-chat", script));
    }
    out
}

fn anthropic_cases() -> Vec<Case> {
    let efforts = [Effort::Off, Effort::Low, Effort::High];
    let caches = [Retention::Off, Retention::Short, Retention::Long];
    let mut out = Vec::new();
    for at in 0..4 {
        for effort in efforts {
            for cache in caches {
                for oauth in [false, true] {
                    out.push(Case {
                        effort,
                        cache,
                        oauth,
                        messages: history(at),
                        ..base("anthropic", "an-text")
                    });
                }
            }
        }
    }
    out.push(Case {
        effort: Effort::High,
        max_output: 2000,
        ..base("anthropic", "an-text")
    });
    out.push(Case {
        tools: vec![],
        system: None,
        cache: Retention::Short,
        ..base("anthropic", "an-text")
    });
    out.push(Case {
        oauth: true,
        system: Some(IDENTITY.into()),
        ..base("anthropic", "an-text")
    });
    out.push(Case {
        oauth: true,
        system: None,
        ..base("anthropic", "an-text")
    });
    for script in [
        "an-tools",
        "an-limit",
        "an-unfinished",
        "an-ping",
        "err-429",
        "err-401",
        "err-500",
    ] {
        out.push(base("anthropic", script));
    }
    out
}

fn gemini_cases() -> Vec<Case> {
    let efforts = [Effort::Off, Effort::Low, Effort::High];
    let mut out = Vec::new();
    for at in 0..4 {
        for effort in efforts {
            out.push(Case {
                effort,
                messages: history(at),
                ..base("gemini", "gm-text")
            });
        }
    }
    out.push(Case {
        effort: Effort::High,
        max_output: 1500,
        ..base("gemini", "gm-text")
    });
    out.push(Case {
        tools: vec![],
        system: None,
        ..base("gemini", "gm-text")
    });
    for script in [
        "gm-tools",
        "gm-limit",
        "gm-unfinished",
        "err-429",
        "err-401",
        "err-500",
    ] {
        out.push(base("gemini", script));
    }
    out
}

fn cases() -> Vec<Case> {
    [openai_cases(), anthropic_cases(), gemini_cases()]
        .into_iter()
        .flatten()
        .collect()
}

fn request(case: &Case, id: &str, url: &str) -> Value {
    let auth = if case.oauth {
        json!({"key": "sk-test", "oauth": {
            "token": "oauth-token",
            "headers": {"anthropic-beta": "claude-code-20250219,oauth-2025-04-20"},
            "identity_prompt": IDENTITY,
        }})
    } else {
        json!({"key": "sk-test"})
    };
    json!({
        "model": "m",
        "system": case.system,
        "messages": case.messages,
        "tools": case.tools,
        "effort": case.effort.name(),
        "max_output": case.max_output,
        "cache": case.cache.name(),
        "provider": {
            "id": "p",
            "base_url": format!("{url}/case/{id}/{}/{}/v1", case.script, case.host),
            "compat": case.compat,
        },
        "auth": auth,
    })
}

fn oa(delta: &Value, finish: Option<&str>, usage: Option<&Value>) -> String {
    let mut body = json!({"choices": [{"index": 0, "delta": delta, "finish_reason": finish}]});
    if let Some(usage) = usage {
        body["usage"] = usage.clone();
    }
    format!("data: {body}")
}

fn oa_usage(usage: &Value) -> String {
    format!("data: {}", json!({"choices": [], "usage": usage}))
}

fn call_delta(
    index: usize,
    id: Option<&str>,
    name: Option<&str>,
    arguments: Option<&str>,
) -> Value {
    let mut call = json!({"index": index});
    if let Some(id) = id {
        call["id"] = json!(id);
        call["type"] = json!("function");
    }
    let mut function = Map::new();
    if let Some(name) = name {
        function.insert("name".into(), json!(name));
    }
    if let Some(arguments) = arguments {
        function.insert("arguments".into(), json!(arguments));
    }
    if !function.is_empty() {
        call["function"] = Value::Object(function);
    }
    json!({"tool_calls": [call]})
}

fn an(kind: &str, mut fields: Value) -> String {
    fields["type"] = json!(kind);
    format!("event: {kind}\ndata: {fields}")
}

fn gm(parts: Option<Value>, finish: Option<&str>, usage: Option<Value>) -> String {
    let mut candidate = json!({});
    if let Some(parts) = parts {
        candidate["content"] = json!({"role": "model", "parts": parts});
    }
    if let Some(finish) = finish {
        candidate["finishReason"] = json!(finish);
    }
    let mut body = json!({"candidates": [candidate]});
    if let Some(usage) = usage {
        body["usageMetadata"] = usage;
    }
    format!("data: {body}")
}

fn done() -> String {
    String::from("data: [DONE]")
}

fn openai_lines(name: &str) -> Option<Vec<String>> {
    let usage = json!({"prompt_tokens": 100, "completion_tokens": 20});
    let stop = Some("stop");
    Some(match name {
        "oa-text" => vec![
            oa(&json!({"role": "assistant", "content": ""}), None, None),
            oa(&json!({"content": "Hello"}), None, None),
            oa(&json!({"content": " world"}), None, None),
            oa(&json!({}), stop, None),
            oa_usage(&usage),
            done(),
        ],
        "oa-think" => vec![
            String::from(": keepalive"),
            oa(&json!({"reasoning_content": "Let me "}), None, None),
            oa(&json!({"reasoning_content": "think."}), None, None),
            oa(&json!({"content": "Done."}), None, None),
            oa(
                &json!({}),
                stop,
                Some(
                    &json!({"prompt_tokens": 50, "completion_tokens": 9, "prompt_tokens_details": {"cached_tokens": 30}}),
                ),
            ),
            done(),
        ],
        "oa-tools" => vec![
            oa(
                &call_delta(0, Some("call_a"), Some("read_file"), Some("")),
                None,
                None,
            ),
            oa(&call_delta(0, None, None, Some(r#"{"path":"#)), None, None),
            oa(&call_delta(0, None, None, Some(r#""a.rs"}"#)), None, None),
            oa(
                &call_delta(
                    1,
                    Some("call_b"),
                    Some("run_command"),
                    Some(r#"{"command":"ls"}"#),
                ),
                None,
                None,
            ),
            oa(
                &json!({}),
                Some("tool_calls"),
                Some(
                    &json!({"prompt_tokens": 70, "completion_tokens": 5, "prompt_cache_hit_tokens": 60}),
                ),
            ),
            done(),
        ],
        "oa-noid" => vec![
            oa(&json!({"content": "x"}), None, None),
            oa(
                &call_delta(0, None, Some("run_command"), Some(r#"{"command":"pwd"}"#)),
                None,
                None,
            ),
            oa(&json!({}), Some("tool_calls"), None),
            done(),
        ],
        "oa-usage" => vec![
            oa(&json!({"content": "u"}), None, None),
            oa(
                &json!({}),
                stop,
                Some(
                    &json!({"prompt_tokens": 90, "completion_tokens": 3, "cached_tokens": 40, "prompt_tokens_details": {"cache_write_tokens": 10}}),
                ),
            ),
            done(),
        ],
        _ => return None,
    })
}

fn openai_cut_lines(name: &str) -> Option<Vec<String>> {
    let stop = Some("stop");
    Some(match name {
        "oa-length" => vec![
            oa(&json!({"content": "cut"}), None, None),
            oa(&json!({}), Some("length"), None),
            done(),
        ],
        "oa-done-only" => vec![oa(&json!({"content": "fine"}), None, None), done()],
        "oa-unfinished" => vec![oa(&json!({"content": "half"}), None, None)],
        "oa-empty" => vec![oa(&json!({}), stop, None), done()],
        "oa-cutcall" => vec![
            oa(
                &call_delta(0, Some("c"), Some("edit_file"), Some(r#"{"path": "a"#)),
                None,
                None,
            ),
            oa(&json!({}), Some("tool_calls"), None),
            done(),
        ],
        "oa-garbage" => vec![
            String::from("data: {not json"),
            oa(&json!({"content": "ok"}), None, None),
            oa(&json!({}), stop, None),
            done(),
        ],
        _ => return None,
    })
}

fn anthropic_lines(name: &str) -> Option<Vec<String>> {
    Some(match name {
        "an-text" => vec![
            an(
                "message_start",
                json!({"message": {"usage": {"input_tokens": 12, "output_tokens": 1, "cache_read_input_tokens": 100, "cache_creation_input_tokens": 7}}}),
            ),
            an(
                "content_block_start",
                json!({"index": 0, "content_block": {"type": "thinking", "thinking": ""}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 0, "delta": {"type": "thinking_delta", "thinking": "hmm"}}),
            ),
            an(
                "content_block_start",
                json!({"index": 1, "content_block": {"type": "text", "text": ""}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 1, "delta": {"type": "text_delta", "text": "Hi"}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 1, "delta": {"type": "text_delta", "text": " there"}}),
            ),
            an(
                "message_delta",
                json!({"delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 15}}),
            ),
            an("message_stop", json!({})),
        ],
        "an-tools" => vec![
            an(
                "message_start",
                json!({"message": {"usage": {"input_tokens": 5, "output_tokens": 1}}}),
            ),
            an(
                "content_block_start",
                json!({"index": 0, "content_block": {"type": "text", "text": ""}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 0, "delta": {"type": "text_delta", "text": "Reading."}}),
            ),
            an(
                "content_block_start",
                json!({"index": 1, "content_block": {"type": "tool_use", "id": "toolu_1", "name": "read_file", "input": {}}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 1, "delta": {"type": "input_json_delta", "partial_json": "{\"pa"}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 1, "delta": {"type": "input_json_delta", "partial_json": "th\": \"b.rs\"}"}}),
            ),
            an(
                "content_block_start",
                json!({"index": 2, "content_block": {"type": "tool_use", "id": "toolu_2", "name": "run_command", "input": {}}}),
            ),
            an(
                "message_delta",
                json!({"delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 30}}),
            ),
            an("message_stop", json!({})),
        ],
        _ => return None,
    })
}

fn anthropic_cut_lines(name: &str) -> Option<Vec<String>> {
    Some(match name {
        "an-limit" => vec![
            an(
                "message_start",
                json!({"message": {"usage": {"input_tokens": 5}}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 0, "delta": {"type": "text_delta", "text": "cut"}}),
            ),
            an(
                "message_delta",
                json!({"delta": {"stop_reason": "max_tokens"}, "usage": {"output_tokens": 8}}),
            ),
            an("message_stop", json!({})),
        ],
        "an-unfinished" => vec![
            an(
                "message_start",
                json!({"message": {"usage": {"input_tokens": 5}}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 0, "delta": {"type": "text_delta", "text": "half"}}),
            ),
        ],
        "an-ping" => vec![
            String::from("event: ping\ndata: {\"type\": \"ping\"}"),
            an(
                "message_start",
                json!({"message": {"usage": {"input_tokens": 1}}}),
            ),
            an(
                "content_block_delta",
                json!({"index": 0, "delta": {"type": "text_delta", "text": "p"}}),
            ),
            an("message_stop", json!({})),
        ],
        _ => return None,
    })
}

fn gemini_lines(name: &str) -> Option<Vec<String>> {
    Some(match name {
        "gm-text" => vec![
            gm(
                Some(json!([{"text": "thinking...", "thought": true}])),
                None,
                None,
            ),
            gm(Some(json!([{"text": "Hello"}])), None, None),
            gm(
                Some(json!([{"text": " there"}])),
                Some("STOP"),
                Some(
                    json!({"promptTokenCount": 40, "candidatesTokenCount": 6, "cachedContentTokenCount": 10, "thoughtsTokenCount": 4}),
                ),
            ),
        ],
        "gm-tools" => vec![gm(
            Some(json!([
                {"text": "Calling."},
                {"functionCall": {"name": "read_file", "args": {"path": "c.rs"}}},
                {"functionCall": {"name": "run_command", "args": {}}},
            ])),
            Some("STOP"),
            Some(json!({"promptTokenCount": 9, "candidatesTokenCount": 2})),
        )],
        "gm-limit" => vec![gm(Some(json!([{"text": "cut"}])), Some("MAX_TOKENS"), None)],
        "gm-unfinished" => vec![gm(Some(json!([{"text": "half"}])), None, None)],
        _ => return None,
    })
}

fn status(name: &str) -> Option<Reply> {
    Some(match name {
        "err-429" => Reply::Status {
            code: 429,
            headers: vec![("retry-after", String::from("7"))],
            body: String::from(r#"{"error": {"message": "slow down"}}"#),
        },
        "err-401" => Reply::Status {
            code: 401,
            headers: Vec::new(),
            body: String::from(r#"{"error": "bad key"}"#),
        },
        "err-500" => Reply::Status {
            code: 500,
            headers: Vec::new(),
            body: String::from("  upstream exploded  "),
        },
        "err-400" => Reply::Status {
            code: 400,
            headers: Vec::new(),
            body: "x".repeat(2500),
        },
        _ => return None,
    })
}

fn script(name: &str) -> Reply {
    openai_lines(name)
        .or_else(|| openai_cut_lines(name))
        .or_else(|| anthropic_lines(name))
        .or_else(|| anthropic_cut_lines(name))
        .or_else(|| gemini_lines(name))
        .map(Reply::Lines)
        .or_else(|| status(name))
        .unwrap_or_else(|| Reply::Status {
            code: 404,
            headers: Vec::new(),
            body: format!("no script named {name}"),
        })
}

fn normalize(value: Value) -> Value {
    match value {
        Value::Object(map) => Value::Object(
            map.into_iter()
                .map(|(key, value)| {
                    let value = match value {
                        Value::String(text) if key == "arguments" => {
                            serde_json::from_str(&text).unwrap_or(Value::String(text))
                        }
                        other => normalize(other),
                    };
                    (key, value)
                })
                .collect(),
        ),
        Value::Array(items) => Value::Array(items.into_iter().map(normalize).collect()),
        other => other,
    }
}

fn observed(request: &Request) -> (String, Value) {
    let parts: Vec<&str> = request.path.split('/').collect();
    let headers: BTreeMap<&str, &String> = HEADERS
        .iter()
        .filter_map(|name| request.headers.get(*name).map(|value| (*name, value)))
        .collect();
    let seen = json!({
        "path": format!("/{}", parts[4..].join("/")),
        "headers": headers,
        "body": normalize(request.body.clone()),
    });
    (parts[2].to_string(), seen)
}

#[test]
fn lua_wires_match_the_rust_providers_they_replaced() {
    let server = Server::start(|request: &Request| {
        let name = request
            .path
            .split('/')
            .nth(3)
            .unwrap_or_default()
            .to_string();
        script(&name)
    })
    .unwrap();
    let sandbox = Sandbox::new("wires").unwrap();
    let lines: Vec<String> = cases()
        .iter()
        .enumerate()
        .map(|(at, case)| {
            let id = format!("k{at:03}");
            json!({"case": id, "wire": case.wire, "request": request(case, &id, &server.url)})
                .to_string()
        })
        .collect();
    let input = sandbox.root().join("cases.jsonl");
    let output = sandbox.root().join("results.jsonl");
    std::fs::write(&input, lines.join("\n") + "\n").unwrap();
    sandbox
        .config(&format!(
            "local CASES, OUT = {:?}, {:?}\n{HARNESS}",
            input.display().to_string(),
            output.display().to_string()
        ))
        .unwrap();
    sandbox
        .run(Until::Title("finished"), &[], Duration::from_secs(60))
        .unwrap();

    let requests: BTreeMap<String, Value> = server.requests().iter().map(observed).collect();
    let results: BTreeMap<String, Value> = std::fs::read_to_string(&output)
        .unwrap()
        .lines()
        .map(|line| {
            let row: Value = serde_json::from_str(line).unwrap();
            let case = row["case"].as_str().unwrap().to_string();
            (
                case,
                normalize(json!({"result": row["result"], "deltas": row["deltas"]})),
            )
        })
        .collect();
    let expected: Vec<Value> = include_str!("fixtures/wires.jsonl")
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(expected.len(), lines.len());
    for want in expected {
        let case = want["case"].as_str().unwrap();
        let sent = json!({"path": want["path"], "headers": want["headers"], "body": normalize(want["body"].clone())});
        assert_eq!(requests.get(case), Some(&sent), "request for {case}");
        let answered = normalize(json!({"result": want["result"], "deltas": want["deltas"]}));
        assert_eq!(results.get(case), Some(&answered), "result for {case}");
    }
}
