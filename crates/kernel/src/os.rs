use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use uji_macros::{constant, function, options};

use crate::kernel::{Restart, State};

#[function(os)]
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .and_then(|elapsed| i64::try_from(elapsed.as_millis()).ok())
        .unwrap_or_default()
}

#[function(os)]
fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|value| !value.is_empty())
}

#[function(os)]
fn cwd() -> mlua::Result<String> {
    Ok(std::env::current_dir()?.display().to_string())
}

#[function(os)]
fn home() -> Option<String> {
    std::env::home_dir().map(|dir| dir.display().to_string())
}

pub(crate) fn home_relative(path: &str) -> Option<(PathBuf, &str)> {
    let after = path.strip_prefix('~')?;
    let rest = match after.strip_prefix(std::path::is_separator) {
        Some(rest) => rest,
        None if after.is_empty() => after,
        None => return None,
    };
    Some((std::env::home_dir()?, rest))
}

pub(crate) fn expanded(path: &str) -> PathBuf {
    match home_relative(path) {
        Some((home, "")) => home,
        Some((home, rest)) => home.join(rest),
        None => PathBuf::from(path),
    }
}

#[function(os)]
fn expand(path: &str) -> String {
    expanded(path).display().to_string()
}

#[function(os)]
fn shorten(path: &str) -> String {
    let Some(home) = std::env::home_dir() else {
        return path.to_string();
    };
    match Path::new(path).strip_prefix(&home) {
        Ok(rest) if rest.as_os_str().is_empty() => "~".to_string(),
        Ok(rest) => Path::new("~").join(rest).display().to_string(),
        Err(_) => path.to_string(),
    }
}

#[function(os)]
fn clock(state: &State) -> f64 {
    state.started.elapsed().as_secs_f64()
}

#[options]
struct RestartOptions {
    #[serde(default)]
    args: Vec<String>,
    #[serde(default)]
    roots: Vec<String>,
    carry: Option<String>,
}

#[function(os)]
fn restart(state: &mut State, opts: RestartOptions) {
    state.restart = Some(Restart {
        args: opts.args,
        roots: opts.roots.into_iter().map(PathBuf::from).collect(),
        carry: opts.carry,
    });
    state.wake();
}

#[function(os)]
fn exit(state: &mut State, code: Option<u8>) {
    state.exit = Some(code.unwrap_or(0));
    state.wake();
}

#[constant(os)]
fn platform() -> &'static str {
    let os = std::env::consts::OS;
    if matches!(os, "macos" | "linux" | "windows") {
        os
    } else {
        "other"
    }
}

#[constant(os)]
fn library() -> &'static str {
    std::env::consts::DLL_EXTENSION
}

#[constant(os)]
fn executable() -> Option<String> {
    std::env::current_exe()
        .ok()
        .map(|path| path.display().to_string())
}

#[constant(os)]
fn argv(state: &State) -> Vec<String> {
    state.args.clone()
}

#[constant(os)]
fn roots(state: &State) -> Vec<String> {
    state.roots.clone()
}

#[constant(os)]
fn carry(state: &State) -> Option<String> {
    state.carry.clone()
}
