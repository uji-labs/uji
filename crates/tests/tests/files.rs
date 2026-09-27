use std::io;

use serde_json::Value;
use uji_tests::Sandbox;

struct Files<'a> {
    sandbox: &'a Sandbox,
}

impl Files<'_> {
    fn around(&self, target: &str, line: usize, count: usize) -> io::Result<Vec<String>> {
        let seen = self
            .sandbox
            .probe(&format!(
                r#"
                local Roots = require("uji.system.roots")
                local roots = Roots(require("uji.app").session.directory, {{}}, false)
                local lines, err = roots:around({target:?}, {line}, {count})
                emit(lines and {{ ok = uji.json.array(lines) }} or {{ err = err }})
            "#
            ))
            .map_err(|err| io::Error::other(err.to_string()))?;
        match &seen[0] {
            Value::Object(found) if found.contains_key("ok") => Ok(found["ok"]
                .as_array()
                .map(|lines| {
                    lines
                        .iter()
                        .filter_map(Value::as_str)
                        .map(String::from)
                        .collect()
                })
                .unwrap_or_default()),
            other => Err(io::Error::other(
                other["err"].as_str().unwrap_or_default().to_string(),
            )),
        }
    }
}

fn files(sandbox: &Sandbox) -> Files<'_> {
    Files { sandbox }
}

#[test]
fn a_preview_numbers_the_lines_around_a_hit() {
    let sandbox = Sandbox::new("files").unwrap();
    let rows = (1..=300)
        .map(|n| format!("row {n}"))
        .collect::<Vec<_>>()
        .join("\n")
        + "\n";
    sandbox.file("rows.txt", rows).unwrap();
    let preview = files(&sandbox).around("rows.txt", 150, 4).unwrap();
    assert_eq!(
        preview,
        [
            "  149| row 149",
            "  150| row 150",
            "  151| row 151",
            "  152| row 152"
        ]
    );
    let early = files(&sandbox).around("rows.txt", 1, 3).unwrap();
    assert_eq!(early, ["    1| row 1", "    2| row 2", "    3| row 3"]);
    assert!(
        files(&sandbox)
            .around("rows.txt", 400, 4)
            .unwrap()
            .is_empty()
    );
}

#[test]
fn a_preview_drops_carriage_returns_and_refuses_what_it_cannot_show() {
    let sandbox = Sandbox::new("files").unwrap();
    sandbox.file("crlf.txt", "a\r\nb\r\n").unwrap();
    sandbox.file("bin.dat", b"x\0y").unwrap();
    sandbox.file("dir/inner.txt", "inside").unwrap();
    assert_eq!(
        files(&sandbox).around("crlf.txt", 1, 2).unwrap(),
        ["    1| a", "    2| b"]
    );
    let binary = files(&sandbox).around("bin.dat", 1, 2).unwrap_err();
    assert_eq!(binary.to_string(), "bin.dat looks like a binary file");
    let directory = files(&sandbox).around("dir", 1, 2).unwrap_err();
    assert_eq!(directory.to_string(), "dir is a directory, not a file");
}
