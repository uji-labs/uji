use std::ffi::OsString;
use std::io::{BufRead, BufReader};
use std::path::{Component, Path, PathBuf};
use std::time::UNIX_EPOCH;

use mlua::{BString, Variadic};
use tokio::io::AsyncWriteExt;
use uji_macros::{function, options, value};

use crate::io::{self, Blocked};
use crate::os;

#[value]
#[derive(Clone, Copy)]
#[serde(rename_all = "lowercase")]
enum Kind {
    Dir,
    File,
    Link,
    Other,
}

#[value]
struct Entry {
    name: String,
    #[serde(rename = "type")]
    kind: Kind,
}

#[value]
struct Stat {
    #[serde(rename = "type")]
    kind: Kind,
    size: u64,
    modified: Option<i64>,
}

fn kind(file_type: std::fs::FileType) -> Kind {
    if file_type.is_dir() {
        Kind::Dir
    } else if file_type.is_file() {
        Kind::File
    } else if file_type.is_symlink() {
        Kind::Link
    } else {
        Kind::Other
    }
}

fn stat_of(metadata: &std::fs::Metadata) -> Stat {
    Stat {
        kind: kind(metadata.file_type()),
        size: metadata.len(),
        modified: metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .and_then(|elapsed| i64::try_from(elapsed.as_millis()).ok()),
    }
}

const NEWLINE: u8 = b'\n';
const BUFFER: usize = 64 * 1024;

#[value]
#[derive(Default)]
struct Excerpt {
    lines: Vec<String>,
    cut: Vec<usize>,
    total: Option<usize>,
    binary: bool,
}

#[options]
struct Window {
    #[serde(default = "first")]
    from: usize,
    #[serde(default = "unlimited")]
    count: usize,
    #[serde(default = "unlimited")]
    max: usize,
    #[serde(default)]
    sniff: usize,
    #[serde(default)]
    total: bool,
}

fn first() -> usize {
    1
}

fn unlimited() -> usize {
    usize::MAX
}

#[options]
struct WriteOptions {
    mode: Option<u32>,
    #[serde(default)]
    append: bool,
}

#[options]
struct RemoveOptions {
    #[serde(default)]
    recursive: bool,
}

impl Window {
    fn read(&self, path: &str) -> std::io::Result<Excerpt> {
        let file = std::fs::File::open(path)?;
        let mut reader = BufReader::with_capacity(BUFFER.max(self.sniff), file);
        let mut excerpt = Excerpt::default();
        if self.sniff > 0 {
            let head = reader.fill_buf()?;
            if head[..head.len().min(self.sniff)].contains(&0) {
                excerpt.binary = true;
                return Ok(excerpt);
            }
        }
        let mut number = 0usize;
        let mut line = Vec::new();
        loop {
            let wanted = number.saturating_add(1) >= self.from && excerpt.lines.len() < self.count;
            if !wanted && !self.total && excerpt.lines.len() >= self.count {
                break;
            }
            let keep = if wanted { self.max } else { 0 };
            let Some(truncated) = next_line(&mut reader, &mut line, keep)? else {
                break;
            };
            number = number.saturating_add(1);
            if wanted {
                excerpt
                    .lines
                    .push(String::from_utf8_lossy(&line).into_owned());
                if truncated {
                    excerpt.cut.push(excerpt.lines.len());
                }
            }
        }
        if self.total {
            excerpt.total = Some(number);
        }
        Ok(excerpt)
    }
}

fn next_line(
    reader: &mut impl BufRead,
    line: &mut Vec<u8>,
    keep: usize,
) -> std::io::Result<Option<bool>> {
    line.clear();
    let mut started = false;
    let mut truncated = false;
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(started.then_some(truncated));
        }
        started = true;
        let ended = memchr::memchr(NEWLINE, available);
        let chunk = ended.map_or(available, |at| &available[..at]);
        let take = chunk.len().min(keep.saturating_sub(line.len()));
        line.extend_from_slice(&chunk[..take]);
        truncated |= take < chunk.len();
        let consumed = chunk.len().saturating_add(usize::from(ended.is_some()));
        reader.consume(consumed);
        if ended.is_some() {
            return Ok(Some(truncated));
        }
    }
}

#[function(fs)]
async fn read(path: String) -> std::io::Result<BString> {
    tokio::fs::read(path).await.map(BString::from)
}

#[function(fs)]
async fn lines(path: String, window: Window) -> Result<Excerpt, Blocked<std::io::Error>> {
    io::blocking(move || window.read(&path)).await
}

#[function(fs)]
async fn write(path: String, data: &[u8], opts: WriteOptions) -> std::io::Result<()> {
    let mut options = tokio::fs::OpenOptions::new();
    options.write(true).create(true);
    if opts.append {
        options.append(true);
    } else {
        options.truncate(true);
    }
    #[cfg(unix)]
    if let Some(mode) = opts.mode {
        options.mode(mode);
    }
    let mut file = options.open(PathBuf::from(path)).await?;
    file.write_all(data).await?;
    file.flush().await
}

#[function(fs)]
async fn list(path: String) -> std::io::Result<Vec<Entry>> {
    let mut reader = tokio::fs::read_dir(path).await?;
    let mut entries = Vec::new();
    while let Some(entry) = reader.next_entry().await? {
        entries.push(Entry {
            name: entry.file_name().to_string_lossy().into_owned(),
            kind: kind(entry.file_type().await?),
        });
    }
    entries.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(entries)
}

#[function(fs)]
async fn stat(path: String) -> std::io::Result<Stat> {
    Ok(stat_of(&tokio::fs::metadata(path).await?))
}

#[function(fs)]
async fn mkdir(path: String) -> std::io::Result<()> {
    tokio::fs::create_dir_all(path).await
}

#[function(fs)]
async fn remove(path: String, opts: RemoveOptions) -> std::io::Result<()> {
    delete(path, opts.recursive).await
}

#[function(fs)]
async fn rename(from: String, to: String) -> std::io::Result<()> {
    tokio::fs::rename(from, to).await
}

fn normalized(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match (part, out.components().next_back()) {
            (Component::CurDir, _)
            | (Component::ParentDir, Some(Component::RootDir | Component::Prefix(_))) => {}
            (Component::ParentDir, Some(Component::Normal(_))) => {
                out.pop();
            }
            _ => out.push(part),
        }
    }
    out
}

#[function(fs)]
async fn resolve(directory: &str, path: &str) -> String {
    access_path(&Path::new(directory).join(os::expanded(path)))
        .await
        .display()
        .to_string()
}

async fn access_path(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match (part, out.components().next_back()) {
            (Component::CurDir, _)
            | (Component::ParentDir, Some(Component::RootDir | Component::Prefix(_))) => {}
            (Component::ParentDir, Some(Component::Normal(_))) => {
                // Removing a symlink before `..` changes the path the OS accesses.
                let cancel = match tokio::fs::symlink_metadata(&out).await {
                    Ok(metadata) => metadata.is_dir(),
                    Err(error) => error.kind() == std::io::ErrorKind::NotFound,
                };
                if cancel {
                    out.pop();
                } else {
                    out.push(part);
                }
            }
            _ => out.push(part),
        }
    }
    out
}

#[function(fs)]
fn absolute(path: &str) -> bool {
    Path::new(path).is_absolute()
}

#[function(fs)]
fn join(base: &str, parts: Variadic<String>) -> String {
    parts
        .into_iter()
        .fold(PathBuf::from(base), |joined, part| joined.join(part))
        .display()
        .to_string()
}

#[function(fs)]
fn parent(path: &str) -> Option<String> {
    Path::new(path)
        .parent()
        .map(|dir| dir.display().to_string())
}

#[function(fs)]
fn name(path: &str) -> Option<String> {
    Path::new(path)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
}

#[function(fs)]
fn inside(path: &str, root: &str) -> bool {
    normalized(Path::new(path)).starts_with(normalized(Path::new(root)))
}

#[function(fs)]
async fn glob(
    directory: String,
    pattern: String,
) -> Result<Vec<String>, Blocked<glob::PatternError>> {
    let (base, rest, relative) = match os::home_relative(&pattern) {
        Some((home, rest)) => (home, rest, false),
        None => (
            PathBuf::from(&directory),
            pattern.as_str(),
            Path::new(&pattern).is_relative(),
        ),
    };
    let full = Path::new(&glob::Pattern::escape(&base.to_string_lossy())).join(rest);
    let matches =
        io::blocking(move || Ok(glob::glob(&full.to_string_lossy())?.collect::<Vec<_>>())).await?;
    let mut out = Vec::with_capacity(matches.len());
    for found in matches.into_iter().flatten() {
        let found = access_path(&found).await;
        let shown = if relative {
            match found.strip_prefix(&base) {
                Ok(inside) => inside,
                _ => &found,
            }
        } else {
            &found
        };
        out.push(shown.display().to_string());
    }
    Ok(out)
}

#[function(fs)]
async fn realpath(path: String) -> std::io::Result<String> {
    Ok(tokio::fs::canonicalize(path).await?.display().to_string())
}

const HOPS: usize = 40;

fn anchored(dir: &Path, target: &Path) -> PathBuf {
    if target.is_absolute() {
        target.to_path_buf()
    } else {
        dir.join(target)
    }
}

fn split(path: &Path) -> Option<(PathBuf, OsString)> {
    let name = path.file_name()?.to_os_string();
    let dir = match path.parent() {
        Some(parent) if parent.as_os_str().is_empty() => PathBuf::from("."),
        Some(parent) => parent.to_path_buf(),
        None => return None,
    };
    Some((dir, name))
}

// The operating system follows a dangling link at the end of a path when it
// creates or reads a file, so canonical has to spell the resolved target.
async fn dereferenced(path: &Path) -> std::io::Result<PathBuf> {
    let mut candidate = path.to_path_buf();
    for _ in 0..HOPS {
        match tokio::fs::canonicalize(&candidate).await {
            Ok(found) => return Ok(found),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => return Ok(candidate),
        }
        let Some((dir, name)) = split(&candidate) else {
            return Ok(candidate);
        };
        let Ok(base) = tokio::fs::canonicalize(&dir).await else {
            return Ok(candidate);
        };
        let link = base.join(&name);
        match tokio::fs::symlink_metadata(&link).await {
            Ok(entry) if entry.is_symlink() => {}
            _ => return Ok(candidate),
        }
        candidate = anchored(&base, &tokio::fs::read_link(&link).await?);
    }
    Err(std::io::Error::other("symlink loop in path"))
}

#[function(fs)]
async fn canonical(path: String) -> std::io::Result<String> {
    let full = dereferenced(Path::new(&path)).await?;
    let mut head = full.clone();
    let mut kept = 0;
    loop {
        match tokio::fs::canonicalize(&head).await {
            Ok(found) => {
                let mut out = found;
                for part in full.components().skip(full.components().count() - kept) {
                    match part {
                        Component::CurDir => {}
                        Component::ParentDir => {
                            out.pop();
                        }
                        _ => out.push(part),
                    }
                }
                return Ok(out.display().to_string());
            }
            Err(error) => {
                if !head.pop() {
                    return Err(error);
                }
                kept += 1;
            }
        }
    }
}

async fn delete(path: String, recursive: bool) -> std::io::Result<()> {
    let metadata = tokio::fs::symlink_metadata(&path).await?;
    if !metadata.is_dir() {
        return tokio::fs::remove_file(path).await;
    }
    if recursive {
        tokio::fs::remove_dir_all(path).await
    } else {
        tokio::fs::remove_dir(path).await
    }
}
