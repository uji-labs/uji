use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::time::Duration;

use async_trait::async_trait;
use serde_json::{Value, json};

use crate::llm::ToolSpec;

use super::Tool;

const MAX_READ_LINES: usize = 2_000;
const MAX_TOOL_OUTPUT: usize = 24_000;
const MAX_GREP_MATCHES: usize = 200;
const MAX_GREP_DEPTH: usize = 12;
const SKIP_DIRS: &[&str] = &[
    ".git",
    "target",
    "node_modules",
    "build",
    "dist",
    ".venv",
    "vendor",
    "__pycache__",
];

fn schema(props: &Value, required: &[&str]) -> Value {
    json!({
        "type": "object",
        "properties": props,
        "required": required,
        "additionalProperties": false,
    })
}

fn resolve(cwd: &Path, path: &str) -> PathBuf {
    let path = Path::new(path);
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        cwd.join(path)
    }
}

fn display(cwd: &Path, path: &Path) -> String {
    path.strip_prefix(cwd).unwrap_or(path).display().to_string()
}

fn cap(text: String, max: usize) -> String {
    let count = text.chars().count();
    if count <= max {
        return text;
    }
    let head: String = text.chars().take(max).collect();
    format!("{head}\n\n[output truncated: showed {max} of {count} characters]")
}

fn arg(args: &Value, key: &str) -> String {
    args.get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn required(args: &Value, key: &str) -> Result<String, String> {
    let value = arg(args, key);
    if value.is_empty() {
        Err(format!(
            "`{key}` is required and must be a non-empty string"
        ))
    } else {
        Ok(value)
    }
}

fn usize_arg(args: &Value, key: &str) -> Option<usize> {
    args.get(key)
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
}

fn is_probably_binary(bytes: &[u8]) -> bool {
    bytes.iter().take(8_000).any(|byte| *byte == 0)
}

pub struct ReadFile;

#[async_trait]
impl Tool for ReadFile {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "read_file".into(),
            description: "Read a text file and return its contents with 1-based line numbers prefixed as `NNN| `. Read a file before editing it so `edit_file` snippets match exactly. Long files are returned in pages: use `offset` and `limit` to read further. The line numbers are display only - never include them in `edit_file` arguments.".into(),
            parameters: schema(
                &json!({
                    "path": {
                        "type": "string",
                        "description": "Path to the file, absolute or relative to the working directory.",
                    },
                    "offset": {
                        "type": "integer",
                        "description": "1-based line to start at. Defaults to 1.",
                        "minimum": 1,
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Maximum number of lines to return. Defaults to 2000.",
                        "minimum": 1,
                    },
                }),
                &["path"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "path")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let path = required(args, "path")?;
        let target = resolve(cwd, &path);
        if target.is_dir() {
            return Err(format!("{path} is a directory; use list_dir"));
        }
        let bytes = std::fs::read(&target).map_err(|err| format!("read {path}: {err}"))?;
        if is_probably_binary(&bytes) {
            return Err(format!("{path} looks like a binary file"));
        }
        let text = String::from_utf8_lossy(&bytes);
        let total = text.lines().count();
        let offset = usize_arg(args, "offset").unwrap_or(1).max(1);
        let limit = usize_arg(args, "limit").unwrap_or(MAX_READ_LINES).max(1);
        if offset > total && total > 0 {
            return Err(format!(
                "offset {offset} is past the end of {path} ({total} lines)"
            ));
        }
        let mut out = String::new();
        for (index, line) in text.lines().enumerate().skip(offset - 1).take(limit) {
            let _ = writeln!(out, "{:>5}| {line}", index + 1);
        }
        if out.is_empty() {
            return Ok(format!("{path} is empty"));
        }
        let last = (offset + limit - 1).min(total);
        if last < total {
            let _ = write!(
                out,
                "\n[showed lines {offset}-{last} of {total}; call read_file again with offset {} for more]",
                last + 1
            );
        }
        Ok(cap(out, MAX_TOOL_OUTPUT))
    }
}

pub struct EditFile;

#[async_trait]
impl Tool for EditFile {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "edit_file".into(),
            description: "Replace an exact snippet of an existing file, leaving the rest untouched. This is the tool to use for changing code. `old_string` must reproduce the file's current text byte for byte, including indentation and newlines, and must appear exactly once unless `replace_all` is true - include a few surrounding lines to make it unique. Do not include the `NNN| ` line-number prefixes that read_file adds. To delete code, pass an empty `new_string`.".into(),
            parameters: schema(
                &json!({
                    "path": {
                        "type": "string",
                        "description": "Path to the file to edit, absolute or relative to the working directory.",
                    },
                    "old_string": {
                        "type": "string",
                        "description": "Exact text to find, copied verbatim from the file.",
                    },
                    "new_string": {
                        "type": "string",
                        "description": "Text to put in its place. Empty string deletes the snippet.",
                    },
                    "replace_all": {
                        "type": "boolean",
                        "description": "Replace every occurrence instead of requiring exactly one. Defaults to false.",
                    },
                }),
                &["path", "old_string", "new_string"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "path")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let path = required(args, "path")?;
        let old = required(args, "old_string")?;
        let new = arg(args, "new_string");
        let replace_all = args
            .get("replace_all")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if old == new {
            return Err("old_string and new_string are identical".into());
        }
        let target = resolve(cwd, &path);
        let text = std::fs::read_to_string(&target).map_err(|err| format!("read {path}: {err}"))?;
        let Some(at) = text.find(old.as_str()) else {
            return Err(format!(
                "old_string was not found in {path}. Read the file again and copy the snippet exactly, without line-number prefixes."
            ));
        };
        let count = text.matches(old.as_str()).count();
        if count > 1 && !replace_all {
            return Err(format!(
                "old_string matches {count} places in {path}. Add surrounding lines to make it unique, or pass replace_all: true."
            ));
        }
        let updated = if replace_all {
            text.replace(old.as_str(), &new)
        } else {
            text.replacen(old.as_str(), &new, 1)
        };
        std::fs::write(&target, &updated).map_err(|err| format!("write {path}: {err}"))?;
        if replace_all {
            Ok(format!("edited {path}: replaced {count} occurrences"))
        } else {
            Ok(format!(
                "edited {path} at line {}",
                text[..at].lines().count() + 1
            ))
        }
    }
}

pub struct WriteFile;

#[async_trait]
impl Tool for WriteFile {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "write_file".into(),
            description: "Write a file from scratch, creating parent directories as needed. This replaces the entire file, so use it for new files only. To change an existing file use `edit_file` instead - overwriting loses everything you did not include.".into(),
            parameters: schema(
                &json!({
                    "path": {
                        "type": "string",
                        "description": "Path to write, absolute or relative to the working directory.",
                    },
                    "content": {
                        "type": "string",
                        "description": "Complete contents of the file.",
                    },
                }),
                &["path", "content"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "path")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let path = required(args, "path")?;
        let content = arg(args, "content");
        let target = resolve(cwd, &path);
        let existed = target.exists();
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent).map_err(|err| format!("mkdir {path}: {err}"))?;
        }
        std::fs::write(&target, &content).map_err(|err| format!("write {path}: {err}"))?;
        let lines = content.lines().count();
        if existed {
            Ok(format!("overwrote {path} ({lines} lines)"))
        } else {
            Ok(format!("created {path} ({lines} lines)"))
        }
    }
}

pub struct ListDir;

#[async_trait]
impl Tool for ListDir {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "list_dir".into(),
            description: "List the entries of a directory, one per line, marked `dir` or `file`. Use it to orient yourself in an unfamiliar tree. Skips version-control and build directories.".into(),
            parameters: schema(
                &json!({
                    "path": {
                        "type": "string",
                        "description": "Directory to list. Defaults to the working directory.",
                    },
                }),
                &[],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        let path = arg(args, "path");
        if path.is_empty() {
            String::from(".")
        } else {
            path
        }
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let path = self.subject(args);
        let target = resolve(cwd, &path);
        let entries = std::fs::read_dir(&target).map_err(|err| format!("list {path}: {err}"))?;
        let mut rows: Vec<String> = Vec::new();
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let is_dir = entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false);
            if is_dir && SKIP_DIRS.contains(&name.as_str()) {
                continue;
            }
            rows.push(format!("{} {name}", if is_dir { "dir " } else { "file" }));
        }
        if rows.is_empty() {
            return Ok(format!("{path} is empty"));
        }
        rows.sort();
        Ok(cap(rows.join("\n"), MAX_TOOL_OUTPUT))
    }
}

pub struct Grep;

#[async_trait]
impl Tool for Grep {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "grep".into(),
            description: "Search text files for a regular expression and return matching lines as `path:line: text`. Use it to locate symbols, callers, and definitions before reading whole files. Skips binaries, version-control and build directories. Returns at most 200 matches; narrow the pattern or path if you hit the cap.".into(),
            parameters: schema(
                &json!({
                    "pattern": {
                        "type": "string",
                        "description": "Rust regular expression, for example `fn run_agent` or `impl \\w+ for OpenAi`.",
                    },
                    "path": {
                        "type": "string",
                        "description": "File or directory to search. Defaults to the working directory.",
                    },
                    "case_sensitive": {
                        "type": "boolean",
                        "description": "Match case exactly. Defaults to true.",
                    },
                }),
                &["pattern"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        let path = arg(args, "path");
        if path.is_empty() {
            String::from(".")
        } else {
            path
        }
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let pattern = required(args, "pattern")?;
        let case_sensitive = args
            .get("case_sensitive")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let regex = regex::RegexBuilder::new(&pattern)
            .case_insensitive(!case_sensitive)
            .build()
            .map_err(|err| format!("invalid pattern: {err}"))?;
        let target = resolve(cwd, &self.subject(args));
        let mut matches = Vec::new();
        if target.is_file() {
            grep_file(&target, &regex, cwd, &mut matches);
        } else {
            walk_grep(&target, &regex, cwd, 0, &mut matches);
        }
        if matches.is_empty() {
            return Ok(format!("no matches for `{pattern}`"));
        }
        let capped = matches.len() >= MAX_GREP_MATCHES;
        let mut out = matches.join("\n");
        if capped {
            let _ = write!(
                out,
                "\n\n[stopped at {MAX_GREP_MATCHES} matches; narrow the pattern or path]"
            );
        }
        Ok(cap(out, MAX_TOOL_OUTPUT))
    }
}

fn grep_file(path: &Path, regex: &regex::Regex, cwd: &Path, out: &mut Vec<String>) {
    let Ok(bytes) = std::fs::read(path) else {
        return;
    };
    if is_probably_binary(&bytes) {
        return;
    }
    let text = String::from_utf8_lossy(&bytes);
    let name = display(cwd, path);
    for (index, line) in text.lines().enumerate() {
        if out.len() >= MAX_GREP_MATCHES {
            return;
        }
        if regex.is_match(line) {
            let line = line.trim_end();
            let line: String = line.chars().take(400).collect();
            out.push(format!("{name}:{}: {line}", index + 1));
        }
    }
}

fn walk_grep(dir: &Path, regex: &regex::Regex, cwd: &Path, depth: usize, out: &mut Vec<String>) {
    if depth > MAX_GREP_DEPTH || out.len() >= MAX_GREP_MATCHES {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut paths: Vec<PathBuf> = entries.flatten().map(|entry| entry.path()).collect();
    paths.sort();
    for path in paths {
        if out.len() >= MAX_GREP_MATCHES {
            return;
        }
        let name = path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_default();
        if path.is_dir() {
            if name.starts_with('.') || SKIP_DIRS.contains(&name.as_str()) {
                continue;
            }
            walk_grep(&path, regex, cwd, depth + 1, out);
        } else {
            grep_file(&path, regex, cwd, out);
        }
    }
}

pub struct RunCommand;

#[async_trait]
impl Tool for RunCommand {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "run_command".into(),
            description: "Run a shell command in the working directory and return its combined stdout and stderr, plus the exit code when it is non-zero. Use it to build, test, run linters, and inspect the environment. Prefer `read_file`, `edit_file`, `grep`, and `list_dir` for file work. The command is non-interactive: it cannot prompt, and it is killed at the timeout.".into(),
            parameters: schema(
                &json!({
                    "command": {
                        "type": "string",
                        "description": "Shell command, for example `cargo test -p uji`.",
                    },
                    "timeout": {
                        "type": "integer",
                        "description": "Seconds before the command is killed. Defaults to 120.",
                        "minimum": 1,
                    },
                }),
                &["command"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "command")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let command = required(args, "command")?;
        let timeout = args
            .get("timeout")
            .and_then(Value::as_u64)
            .unwrap_or(120)
            .max(1);
        let output = tokio::time::timeout(
            Duration::from_secs(timeout),
            tokio::process::Command::new("sh")
                .arg("-c")
                .arg(&command)
                .current_dir(cwd)
                .output(),
        )
        .await
        .map_err(|_| format!("command timed out after {timeout}s"))?
        .map_err(|err| format!("spawn command: {err}"))?;

        let mut text = String::new();
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stdout.is_empty() {
            text.push_str(&stdout);
        }
        if !stderr.is_empty() {
            if !text.is_empty() {
                text.push('\n');
            }
            text.push_str(&stderr);
        }
        if output.status.success() {
            if text.trim().is_empty() {
                text.push_str("(no output, exit code 0)");
            }
        } else {
            let code = output
                .status
                .code()
                .map_or_else(|| String::from("signal"), |code| code.to_string());
            if !text.is_empty() {
                text.push('\n');
            }
            let _ = write!(text, "(exit code {code})");
        }
        Ok(cap(text, MAX_TOOL_OUTPUT))
    }
}
