use std::path::{Path, PathBuf};

use uji_kernel::{Options, Outcome, Sources, Terminal, VirtualHandle, virtual_terminal};

const ENTRY: &str = "uji.boot";
const SCRIPT: &str = "-l";
const SCREEN: &str = "--screen";

fn script(args: &[String]) -> Option<(Vec<Sources>, String)> {
    let [_, flag, file, ..] = args else {
        return None;
    };
    if flag != SCRIPT {
        return None;
    }
    let path = Path::new(file);
    let entry = path.file_stem()?.to_str()?.to_string();
    let dir = path
        .parent()
        .filter(|dir| !dir.as_os_str().is_empty())
        .map_or_else(|| PathBuf::from("."), Path::to_path_buf);
    Some((vec![Sources::Directory(dir)], entry))
}

fn screen(args: &mut Vec<String>) -> Option<(Terminal, VirtualHandle)> {
    if args.get(1).map(String::as_str) != Some(SCREEN) {
        return None;
    }
    let (width, height) = args.get(2)?.split_once('x')?;
    let (terminal, handle) = virtual_terminal(width.parse().ok()?, height.parse().ok()?);
    args.drain(1..3);
    Some((Terminal::Virtual(terminal), handle))
}

fn main() -> Outcome {
    let mut args: Vec<String> = std::env::args().collect();
    let (sources, entry) = script(&args)
        .unwrap_or_else(|| (vec![Sources::Embedded(uji_lua::FILES)], String::from(ENTRY)));
    let (terminal, handle) = screen(&mut args)
        .map_or((Terminal::Real, None), |(terminal, handle)| {
            (terminal, Some(handle))
        });
    let outcome = uji_kernel::run(Options {
        sources,
        entry,
        args,
        terminal,
        debug: true,
    });
    drop(handle);
    for error in &outcome.errors {
        eprintln!("uji: error: {error}");
    }
    outcome
}
