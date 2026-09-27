use std::error::Error;
use std::fmt::Write as _;
use std::io;
use std::path::{Path, PathBuf};

const ROOT: &str = "uji";

fn main() -> Result<(), Box<dyn Error>> {
    println!("cargo::rerun-if-changed={ROOT}");
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR")?);
    let mut files = Vec::new();
    lua_files(&manifest.join(ROOT), &mut files)?;
    files.sort();
    let mut out = String::from("pub const FILES: &[(&str, &str)] = &[\n");
    for file in &files {
        let parts: Vec<_> = file
            .strip_prefix(&manifest)?
            .components()
            .map(|part| part.as_os_str().to_string_lossy())
            .collect();
        writeln!(
            out,
            "    ({:?}, include_str!({:?})),",
            parts.join("/"),
            file.to_string_lossy()
        )?;
    }
    let version = format!("return {:?}", std::env::var("CARGO_PKG_VERSION")?);
    writeln!(out, "    (\"uji/version.lua\", {version:?}),")?;
    out.push_str("];\n");
    std::fs::write(
        PathBuf::from(std::env::var("OUT_DIR")?).join("files.rs"),
        out,
    )?;
    Ok(())
}

fn lua_files(dir: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let path = entry?.path();
        if path.is_dir() {
            lua_files(&path, out)?;
        } else if path.extension().is_some_and(|ext| ext == "lua") {
            out.push(path);
        }
    }
    Ok(())
}
