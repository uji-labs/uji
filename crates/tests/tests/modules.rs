use std::env::consts::DLL_EXTENSION;
use std::error::Error;
use std::path::PathBuf;
use std::process::Command;

use serde_json::{Value, json};
use uji_tests::Sandbox;

const MANIFEST: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/module/Cargo.toml");
const TARGET: &str = concat!(env!("CARGO_TARGET_TMPDIR"), "/module");

fn library() -> Result<PathBuf, Box<dyn Error>> {
    let output = Command::new(env!("CARGO"))
        .args(["build", "--manifest-path", MANIFEST, "--target-dir", TARGET])
        .args(["--message-format", "json"])
        .output()?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).into_owned().into());
    }
    String::from_utf8(output.stdout)?
        .lines()
        .filter_map(|line| serde_json::from_str::<Value>(line).ok())
        .filter(|message| message["reason"] == "compiler-artifact")
        .filter(|message| message["target"]["kind"] == json!(["cdylib"]))
        .flat_map(|message| message["filenames"].as_array().cloned().unwrap_or_default())
        .filter_map(|file| file.as_str().map(PathBuf::from))
        .find(|file| {
            file.extension()
                .is_some_and(|extension| extension == DLL_EXTENSION)
        })
        .ok_or_else(|| "cargo built no test module".into())
}

fn prepare(sandbox: &Sandbox, relative: &str) -> Result<PathBuf, Box<dyn Error>> {
    let target = sandbox.root().join("cfg").join(relative);
    std::fs::create_dir_all(target.parent().ok_or("a file needs a folder")?)?;
    Ok(target)
}

fn install(sandbox: &Sandbox, name: &str) -> Result<(), Box<dyn Error>> {
    let target = prepare(sandbox, &format!("native/{name}.{DLL_EXTENSION}"))?;
    std::fs::copy(library()?, target)?;
    Ok(())
}

#[test]
fn a_native_module_is_required_like_a_lua_module() {
    let sandbox = Sandbox::new("modules").unwrap();
    install(&sandbox, "testmod").unwrap();
    let seen = sandbox
        .probe(
            r#"
            local module = require("testmod")
            emit(module.add(40, 2))
            emit(module.greet("uji"))
            local ok, err = pcall(module.insist, "not today")
            emit({ ok, tostring(err) })
            emit((pcall(module.add, "forty", 2)))
            "#,
        )
        .unwrap();
    assert_eq!(seen[0], 42);
    assert_eq!(seen[1], "hello uji");
    assert_eq!(seen[2][0], false, "a Rust error becomes a Lua error");
    assert!(
        seen[2][1]
            .as_str()
            .unwrap_or_default()
            .contains("not today")
    );
    assert_eq!(
        seen[3], false,
        "an argument of the wrong type raises an error"
    );
}

#[test]
fn a_native_object_has_fields_and_methods_and_is_freed_by_lua() {
    let sandbox = Sandbox::new("modules").unwrap();
    install(&sandbox, "testmod").unwrap();
    let seen = sandbox
        .probe(
            r#"
            local module = require("testmod")
            local before = module.dropped()
            local counter = module.counter(10, 5)
            emit(counter.start)
            emit(counter:bump())
            emit(counter:bump())
            emit(module.dropped() - before)
            counter = nil
            collectgarbage()
            collectgarbage()
            emit(module.dropped() - before)
            "#,
        )
        .unwrap();
    assert_eq!(seen[0], 10);
    assert_eq!(seen[1], 15);
    assert_eq!(seen[2], 20);
    assert_eq!(seen[3], 0, "the object lives while Lua holds it");
    assert_eq!(
        seen[4], 1,
        "the object is dropped in Rust after Lua collects it"
    );
}

#[test]
fn a_built_in_module_is_replaced_by_one_found_first() {
    let sandbox = Sandbox::new("modules").unwrap();
    install(&sandbox, "uji/sys/sha256").unwrap();
    std::fs::write(
        prepare(&sandbox, "lua/uji/sys/lossy.lua").unwrap(),
        "return function(data) return 'lua ' .. data end",
    )
    .unwrap();
    let seen = sandbox
        .probe(
            r#"
            local sys = require("uji.sys")
            emit(sys.sha256("abc"))
            emit(sys.lossy("abc"))
            emit(uji.base64.encode("abc"))
            "#,
        )
        .unwrap();
    assert_eq!(seen[0], "replaced abc", "a native library replaces it");
    assert_eq!(seen[1], "lua abc", "a Lua file replaces it");
    assert_eq!(seen[2], "YWJj", "the rest stay built in");
}

#[test]
fn a_module_written_while_uji_runs_is_used_after_a_reload() {
    let seen = Sandbox::new("modules")
        .unwrap()
        .probe(
            r#"
            local sys = require("uji.sys")
            local app = require("uji.core.app")
            local before = probe.work .. "/before.json"
            if not sys.os.carry then
                local file = assert(io.open(before, "w"))
                file:write(sys.json.encode({ lossy = sys.lossy("abc"), session = app.session.id }))
                file:close()
                local folder = require("uji.core.paths").config() .. "/lua/uji/sys"
                sys.fs.mkdir(folder)
                sys.fs.write(folder .. "/lossy.lua", "return function(data) return 'reloaded ' .. data end")
                require("uji.core.config").reload()
                return
            end
            local file = assert(io.open(before))
            local earlier = sys.json.decode(file:read("*a"))
            file:close()
            emit(earlier.lossy, sys.lossy("abc"), earlier.session == app.session.id)
            "#,
        )
        .unwrap();
    assert_eq!(seen[0], "abc", "the built-in module ran before the reload");
    assert_eq!(
        seen[1], "reloaded abc",
        "the file written while uji ran replaced it"
    );
    assert_eq!(seen[2], true, "the reload kept the session");
}
