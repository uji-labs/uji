use std::fmt::Write as _;
use std::io::{BufRead, BufReader};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use cap_std::ambient_authority;
use cap_std::fs::Dir;
use serde_json::{Value, json};

use crate::llm::ToolSpec;
use crate::process;
use crate::tools::lines;

use super::{Invocation, Tool};

const MAX_READ_LINES: usize = 2_000;
const MAX_LINE_BYTES: usize = 2_000;
const SNIFF_BYTES: usize = 8_192;
const MAX_TOOL_OUTPUT: usize = 24_000;
const MAX_GREP_MATCHES: usize = 200;
const MAX_LIST_ENTRIES: usize = 1_000;
const MAX_MATCH_CHARS: usize = 400;
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

#[derive(Clone, Default)]
/// Where file tools may reach. Unconfined by default: the whole filesystem is
/// reachable. Turning confinement on restricts tools to the working directory
/// plus any explicitly granted roots.
pub struct Roots {
    extra: Arc<[PathBuf]>,
    confined: bool,
}

impl Roots {
    pub fn new(extra: Vec<PathBuf>) -> Self {
        Self {
            extra: extra.into(),
            confined: false,
        }
    }

    pub fn confined(extra: Vec<PathBuf>) -> Self {
        Self {
            extra: extra.into(),
            confined: true,
        }
    }

    pub fn set_confined(&mut self, confined: bool) {
        self.confined = confined;
    }

    fn candidates<'a>(&'a self, cwd: &'a Path) -> impl Iterator<Item = &'a Path> {
        let anywhere = (!self.confined).then(|| Path::new(ROOT));
        std::iter::once(cwd)
            .chain(self.extra.iter().map(PathBuf::as_path))
            .chain(anywhere)
    }
}

#[cfg(windows)]
const ROOT: &str = "\\";
#[cfg(not(windows))]
const ROOT: &str = "/";

struct Confined {
    dir: Dir,
    rel: PathBuf,
}

fn stays_within(path: &Path) -> bool {
    let mut depth = 0i32;
    for part in path.components() {
        match part {
            Component::ParentDir => depth -= 1,
            Component::Normal(_) => depth += 1,
            _ => {}
        }
        if depth < 0 {
            return false;
        }
    }
    true
}

fn relative_to(root: &Path, path: &Path) -> Option<PathBuf> {
    let rel = if path.is_absolute() {
        path.strip_prefix(root).ok()?.to_path_buf()
    } else if stays_within(path) {
        path.to_path_buf()
    } else {
        return None;
    };
    Some(if rel.as_os_str().is_empty() {
        PathBuf::from(".")
    } else {
        rel
    })
}

fn outside(path: &str, cwd: &Path) -> String {
    format!(
        "{path} is outside the working directory ({}); tools can only reach files under it",
        cwd.display()
    )
}

fn resolve(cwd: &Path, path: &str, roots: &Roots) -> Result<Confined, String> {
    let raw = Path::new(path);
    let (root, rel) = roots
        .candidates(cwd)
        .find_map(|root| relative_to(root, raw).map(|rel| (root, rel)))
        .ok_or_else(|| outside(path, cwd))?;
    let dir = Dir::open_ambient_dir(root, ambient_authority())
        .map_err(|err| format!("open {}: {err}", root.display()))?;
    Ok(Confined { dir, rel })
}

fn fs_error(action: &str, path: &str, cwd: &Path, err: &std::io::Error) -> String {
    if err.kind() == std::io::ErrorKind::PermissionDenied {
        outside(path, cwd)
    } else {
        format!("{action} {path}: {err}")
    }
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

fn spill_path(command: &str) -> Option<PathBuf> {
    let dir = std::env::temp_dir().join("uji-output");
    std::fs::create_dir_all(&dir).ok()?;
    let stem: String = command
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .take(40)
        .collect();
    Some(dir.join(format!("{}-{stem}.log", std::process::id())))
}

fn is_probably_binary(bytes: &[u8]) -> bool {
    bytes.iter().take(8_000).any(|byte| *byte == 0)
}

pub struct ReadFile {
    pub roots: Roots,
}

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

    async fn run(&self, args: &Value, call: &Invocation<'_>) -> Result<String, String> {
        let cwd = call.cwd;
        let path = required(args, "path")?;
        let target = resolve(cwd, &path, &self.roots)?;
        if target.dir.metadata(&target.rel).is_ok_and(|m| m.is_dir()) {
            return Err(format!("{path} is a directory; use list_dir"));
        }
        let file = target
            .dir
            .open(&target.rel)
            .map_err(|err| fs_error("read", &path, cwd, &err))?;
        let mut reader = BufReader::with_capacity(SNIFF_BYTES, file);
        let head = reader
            .fill_buf()
            .map_err(|err| fs_error("read", &path, cwd, &err))?;
        if is_probably_binary(head) {
            return Err(format!("{path} looks like a binary file"));
        }
        let offset = usize_arg(args, "offset").unwrap_or(1).max(1);
        let limit = usize_arg(args, "limit").unwrap_or(MAX_READ_LINES).max(1);

        let mut out = String::new();
        let mut line = String::new();
        let mut total = 0usize;
        let mut shown = 0usize;
        while let lines::Line::Read { truncated } =
            lines::read(&mut reader, &mut line, MAX_LINE_BYTES)
                .map_err(|err| fs_error("read", &path, cwd, &err))?
        {
            if truncated {
                line.push_str(" …[line truncated]");
            }
            total = total.saturating_add(1);
            if total < offset || shown >= limit {
                continue;
            }
            shown = shown.saturating_add(1);
            let _ = writeln!(out, "{total:>5}| {line}");
        }
        if total == 0 {
            return Ok(format!("{path} is empty"));
        }
        if offset > total {
            return Err(format!(
                "offset {offset} is past the end of {path} ({total} lines)"
            ));
        }
        let last = offset.saturating_add(shown).saturating_sub(1);
        if last < total {
            let _ = write!(
                out,
                "\n[showed lines {offset}-{last} of {total}; call read_file again with offset {} for more]",
                last.saturating_add(1)
            );
        }
        Ok(out)
    }
}

pub struct EditFile {
    pub roots: Roots,
}

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

    async fn run(&self, args: &Value, call: &Invocation<'_>) -> Result<String, String> {
        let cwd = call.cwd;
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
        let target = resolve(cwd, &path, &self.roots)?;
        let text = target
            .dir
            .read_to_string(&target.rel)
            .map_err(|err| fs_error("read", &path, cwd, &err))?;
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
        target
            .dir
            .write(&target.rel, &updated)
            .map_err(|err| fs_error("write", &path, cwd, &err))?;
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

pub struct WriteFile {
    pub roots: Roots,
}

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

    async fn run(&self, args: &Value, call: &Invocation<'_>) -> Result<String, String> {
        let cwd = call.cwd;
        let path = required(args, "path")?;
        let content = arg(args, "content");
        let target = resolve(cwd, &path, &self.roots)?;
        let existed = target.dir.metadata(&target.rel).is_ok();
        if let Some(parent) = target.rel.parent().filter(|p| !p.as_os_str().is_empty()) {
            target
                .dir
                .create_dir_all(parent)
                .map_err(|err| fs_error("mkdir", &path, cwd, &err))?;
        }
        target
            .dir
            .write(&target.rel, &content)
            .map_err(|err| fs_error("write", &path, cwd, &err))?;
        let lines = content.lines().count();
        if existed {
            Ok(format!("overwrote {path} ({lines} lines)"))
        } else {
            Ok(format!("created {path} ({lines} lines)"))
        }
    }
}

pub struct ListDir {
    pub roots: Roots,
}

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

    async fn run(&self, args: &Value, call: &Invocation<'_>) -> Result<String, String> {
        let cwd = call.cwd;
        let path = self.subject(args);
        let target = resolve(cwd, &path, &self.roots)?;
        let entries = target
            .dir
            .read_dir(&target.rel)
            .map_err(|err| fs_error("list", &path, cwd, &err))?;
        let mut rows: Vec<String> = Vec::new();
        let mut capped = false;
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let is_dir = entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false);
            if is_dir && SKIP_DIRS.contains(&name.as_str()) {
                continue;
            }
            if rows.len() >= MAX_LIST_ENTRIES {
                capped = true;
                break;
            }
            rows.push(format!("{} {name}", if is_dir { "dir " } else { "file" }));
        }
        if rows.is_empty() {
            return Ok(format!("{path} is empty"));
        }
        rows.sort();
        let mut out = rows.join("\n");
        if capped {
            let _ = write!(
                out,
                "\n\n[stopped at {MAX_LIST_ENTRIES} entries; narrow the path or use grep]"
            );
        }
        Ok(out)
    }
}

pub struct Grep {
    pub roots: Roots,
}

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

    async fn run(&self, args: &Value, call: &Invocation<'_>) -> Result<String, String> {
        let cwd = call.cwd;
        let pattern = required(args, "pattern")?;
        let case_sensitive = args
            .get("case_sensitive")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        let regex = regex::RegexBuilder::new(&pattern)
            .case_insensitive(!case_sensitive)
            .build()
            .map_err(|err| format!("invalid pattern: {err}"))?;
        let path = self.subject(args);
        let target = resolve(cwd, &path, &self.roots)?;
        let mut matches = Vec::new();
        let whole_root = target.rel == Path::new(".");
        if target
            .dir
            .metadata(&target.rel)
            .is_ok_and(|meta| meta.is_file())
        {
            let label = target.rel.display().to_string();
            grep_file(&target.dir, &target.rel, &label, &regex, &mut matches);
        } else {
            let nested = if whole_root {
                None
            } else {
                Some(
                    target
                        .dir
                        .open_dir(&target.rel)
                        .map_err(|err| fs_error("search", &path, cwd, &err))?,
                )
            };
            let dir = nested.as_ref().unwrap_or(&target.dir);
            let prefix = if whole_root {
                PathBuf::new()
            } else {
                target.rel.clone()
            };
            walk_grep(dir, &prefix, &regex, 0, &mut matches);
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

fn grep_file(dir: &Dir, rel: &Path, label: &str, regex: &regex::Regex, out: &mut Vec<String>) {
    let Ok(file) = dir.open(rel) else {
        return;
    };
    let mut reader = BufReader::with_capacity(SNIFF_BYTES, file);
    let Ok(head) = reader.fill_buf() else {
        return;
    };
    if is_probably_binary(head) {
        return;
    }
    let mut line = String::new();
    let mut index = 0usize;
    while let Ok(lines::Line::Read { .. }) = lines::read(&mut reader, &mut line, MAX_LINE_BYTES) {
        index = index.saturating_add(1);
        if out.len() >= MAX_GREP_MATCHES {
            return;
        }
        if regex.is_match(&line) {
            let shown: String = line.trim_end().chars().take(MAX_MATCH_CHARS).collect();
            out.push(format!("{label}:{index}: {shown}"));
        }
    }
}

fn walk_grep(dir: &Dir, prefix: &Path, regex: &regex::Regex, depth: usize, out: &mut Vec<String>) {
    if depth > MAX_GREP_DEPTH || out.len() >= MAX_GREP_MATCHES {
        return;
    }
    let Ok(entries) = dir.entries() else {
        return;
    };
    let mut items: Vec<(String, bool)> = entries
        .flatten()
        .map(|entry| {
            let name = entry.file_name().to_string_lossy().into_owned();
            let is_dir = entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false);
            (name, is_dir)
        })
        .collect();
    items.sort();
    for (name, is_dir) in items {
        if out.len() >= MAX_GREP_MATCHES {
            return;
        }
        let shown = prefix.join(&name);
        if is_dir {
            if name.starts_with('.') || SKIP_DIRS.contains(&name.as_str()) {
                continue;
            }
            if let Ok(nested) = dir.open_dir(&name) {
                walk_grep(&nested, &shown, regex, depth.saturating_add(1), out);
            }
        } else {
            grep_file(
                dir,
                Path::new(&name),
                &shown.display().to_string(),
                regex,
                out,
            );
        }
    }
}

pub struct RunCommand {
    pub roots: Roots,
}

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

    async fn run(&self, args: &Value, call: &Invocation<'_>) -> Result<String, String> {
        let command = required(args, "command")?;
        let timeout = args
            .get("timeout")
            .and_then(Value::as_u64)
            .unwrap_or(120)
            .max(1);
        let mut capture = process::Capture::new(MAX_TOOL_OUTPUT);
        if let Some(path) = spill_path(&command)
            && resolve(call.cwd, &path.to_string_lossy(), &self.roots).is_ok()
        {
            capture = capture.spilling(path);
        }
        let spec = process::Spec::shell(&command)
            .in_dir(call.cwd)
            .within(Duration::from_secs(timeout));
        let exit = process::stream(spec, call.cancel, |_, line| {
            capture.push(&line);
            call.progress.send(line);
        })
        .await
        .map_err(|err| format!("spawn command: {err}"))?;

        let mut text = capture.finish();
        match exit {
            process::Exit::TimedOut => return Err(format!("command timed out after {timeout}s")),
            process::Exit::Cancelled => return Err(String::from("command interrupted")),
            process::Exit::Code(0) => {
                if text.trim().is_empty() {
                    text.push_str("(no output, exit code 0)");
                }
            }
            process::Exit::Code(code) => {
                if !text.is_empty() {
                    text.push('\n');
                }
                let _ = write!(text, "(exit code {code})");
            }
        }
        Ok(text)
    }
}

/// Read `lines` of context centred on `line`, for previewing a search hit.
///
/// Goes through the same [`resolve`] confinement as the file tools, so a
/// preview can never reach somewhere a tool could not.
pub fn read_around(
    cwd: &Path,
    path: &str,
    line: usize,
    lines: usize,
    roots: &Roots,
) -> Result<Vec<String>, String> {
    let target = resolve(cwd, path, roots)?;
    let bytes = target
        .dir
        .read(&target.rel)
        .map_err(|err| fs_error("read", path, cwd, &err))?;
    if is_probably_binary(&bytes) {
        return Err(format!("{path} looks like a binary file"));
    }
    let text = String::from_utf8_lossy(&bytes);
    let start = line.saturating_sub(1).saturating_sub(lines / 4);
    Ok(text
        .lines()
        .enumerate()
        .skip(start)
        .take(lines)
        .map(|(at, text)| format!("{:>5}| {text}", at.saturating_add(1)))
        .collect())
}
