use std::process::ExitCode;

use uji_kernel::{Options, Sources, Terminal};

const ENTRY: &str = "uji.boot";
const RUNTIME: &str = "UJI_RUNTIME";

fn main() -> ExitCode {
    let own = std::env::var_os(RUNTIME).map_or(Sources::Embedded(uji_lua::FILES), |dir| {
        Sources::Directory(dir.into())
    });
    let outcome = uji_kernel::run(Options {
        sources: vec![own],
        entry: String::from(ENTRY),
        args: std::env::args().collect(),
        terminal: Terminal::Real,
        debug: false,
    });
    for error in &outcome.errors {
        eprintln!("uji: error: {error}");
    }
    ExitCode::from(outcome.code)
}
