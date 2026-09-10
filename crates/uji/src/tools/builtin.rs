use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::time::Duration;

use async_trait::async_trait;
use serde_json::{Value, json};

use crate::llm::ToolSpec;

use super::Tool;

fn schema(props: &Value, required: &[&str]) -> Value {
    json!({
        "type": "object",
        "properties": props,
        "required": required,
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

fn truncate(text: String, max: usize) -> String {
    if text.chars().count() <= max {
        text
    } else {
        text.chars().take(max).collect()
    }
}

fn arg(args: &Value, key: &str) -> String {
    args.get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

pub struct ReadFile;

#[async_trait]
impl Tool for ReadFile {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "read_file".into(),
            description: "Read a file's contents".into(),
            parameters: schema(
                &json!({ "path": { "type": "string", "description": "file path" } }),
                &["path"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "path")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let path = arg(args, "path");
        let target = resolve(cwd, &path);
        let text = std::fs::read_to_string(&target).map_err(|err| format!("read {path}: {err}"))?;
        Ok(truncate(text, 20_000))
    }
}

pub struct WriteFile;

#[async_trait]
impl Tool for WriteFile {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "write_file".into(),
            description: "Write content to a file, creating parent directories".into(),
            parameters: schema(
                &json!({
                    "path": { "type": "string", "description": "file path" },
                    "content": { "type": "string", "description": "file content" },
                }),
                &["path", "content"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "path")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let path = arg(args, "path");
        let content = arg(args, "content");
        let target = resolve(cwd, &path);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent).map_err(|err| format!("mkdir {path}: {err}"))?;
        }
        std::fs::write(&target, &content).map_err(|err| format!("write {path}: {err}"))?;
        Ok(format!("wrote {} bytes to {path}", content.len()))
    }
}

pub struct ListDir;

#[async_trait]
impl Tool for ListDir {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "list_dir".into(),
            description: "List the entries of a directory".into(),
            parameters: schema(
                &json!({ "path": { "type": "string", "description": "directory path" } }),
                &["path"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "path")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let path = arg(args, "path");
        let target = resolve(cwd, &path);
        let entries = std::fs::read_dir(&target).map_err(|err| format!("list {path}: {err}"))?;
        let mut out = String::new();
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let kind = entry
                .file_type()
                .map_or("?", |t| if t.is_dir() { "dir" } else { "file" });
            out.push_str(kind);
            out.push(' ');
            out.push_str(&name);
            out.push('\n');
        }
        Ok(truncate(out, 8_000))
    }
}

pub struct Grep;

#[async_trait]
impl Tool for Grep {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "grep".into(),
            description: "Search files under a directory for lines containing a query".into(),
            parameters: schema(
                &json!({
                    "query": { "type": "string", "description": "substring to match" },
                    "path": { "type": "string", "description": "directory to search" },
                }),
                &["query"],
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
        let query = arg(args, "query");
        if query.is_empty() {
            return Err("query is required".into());
        }
        let target = resolve(cwd, &self.subject(args));
        let mut matches = Vec::new();
        walk_grep(&target, &query, 0, &mut matches);
        if matches.is_empty() {
            Ok("no matches".into())
        } else {
            Ok(matches.join("\n"))
        }
    }
}

fn walk_grep(dir: &Path, query: &str, depth: usize, out: &mut Vec<String>) {
    if depth > 6 || out.len() >= 200 {
        return;
    }
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        if out.len() >= 200 {
            return;
        }
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        if path.is_dir() {
            if matches!(name.as_str(), "target" | "node_modules" | "build" | "dist") {
                continue;
            }
            walk_grep(&path, query, depth + 1, out);
        } else if let Ok(text) = std::fs::read_to_string(&path) {
            for (index, line) in text.lines().enumerate() {
                if line.contains(query) {
                    out.push(format!(
                        "{}:{}: {}",
                        path.display(),
                        index + 1,
                        truncate(line.to_string(), 500)
                    ));
                    if out.len() >= 200 {
                        return;
                    }
                }
            }
        }
    }
}

pub struct RunCommand;

#[async_trait]
impl Tool for RunCommand {
    fn spec(&self) -> ToolSpec {
        ToolSpec {
            name: "run_command".into(),
            description: "Run a shell command in the working directory".into(),
            parameters: schema(
                &json!({
                    "command": { "type": "string", "description": "shell command to run" },
                    "timeout": { "type": "number", "description": "seconds before timeout" },
                }),
                &["command"],
            ),
        }
    }

    fn subject(&self, args: &Value) -> String {
        arg(args, "command")
    }

    async fn run(&self, args: &Value, cwd: &Path) -> Result<String, String> {
        let command = arg(args, "command");
        if command.is_empty() {
            return Err("command is required".into());
        }
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
        .map_err(|_| "command timed out".to_string())?
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
        if !output.status.success() {
            let code = output
                .status
                .code()
                .map_or_else(|| String::from("signal"), |code| code.to_string());
            let _ = write!(text, "\n(exit code {code})");
        }
        Ok(truncate(text, 20_000))
    }
}
