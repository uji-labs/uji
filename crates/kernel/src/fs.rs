use std::path::PathBuf;
use std::time::UNIX_EPOCH;

use mlua::{IntoLuaMulti, Lua, LuaSerdeExt, Table, Value};
use serde::Serialize;
use tokio::io::AsyncWriteExt;

use crate::io;

#[derive(Serialize)]
struct Entry {
    name: String,
    #[serde(rename = "type")]
    kind: &'static str,
}

#[derive(Serialize)]
struct Stat {
    #[serde(rename = "type")]
    kind: &'static str,
    size: u64,
    modified: Option<i64>,
}

fn kind(file_type: std::fs::FileType) -> &'static str {
    if file_type.is_dir() {
        "dir"
    } else if file_type.is_file() {
        "file"
    } else if file_type.is_symlink() {
        "link"
    } else {
        "other"
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

struct Write {
    path: PathBuf,
    data: Vec<u8>,
    mode: Option<u32>,
    append: bool,
}

impl Write {
    fn from_args(path: String, data: &mlua::LuaString, opts: Option<&Table>) -> mlua::Result<Self> {
        let option = |key: &str| -> mlua::Result<Option<Value>> {
            opts.map(|opts| opts.get::<Value>(key)).transpose()
        };
        Ok(Self {
            path: PathBuf::from(path),
            data: data.as_bytes().to_vec(),
            mode: match option("mode")? {
                Some(Value::Integer(mode)) => u32::try_from(mode).ok(),
                _ => None,
            },
            append: matches!(option("append")?, Some(Value::Boolean(true))),
        })
    }

    async fn run(self) -> std::io::Result<()> {
        let mut options = tokio::fs::OpenOptions::new();
        options.write(true).create(true);
        if self.append {
            options.append(true);
        } else {
            options.truncate(true);
        }
        #[cfg(unix)]
        if let Some(mode) = self.mode {
            options.mode(mode);
        }
        let mut file = options.open(&self.path).await?;
        file.write_all(&self.data).await?;
        file.flush().await
    }
}

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

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let fs = lua.create_table()?;
    fs.set(
        "read",
        lua.create_async_function(|lua, path: String| async move {
            match io::run(io::handle(&lua)?, tokio::fs::read(path)).await? {
                Ok(bytes) => Value::String(lua.create_string(bytes)?).into_lua_multi(&lua),
                Err(err) => io::failure(&lua, &err),
            }
        })?,
    )?;
    fs.set(
        "write",
        lua.create_async_function(
            |lua, (path, data, opts): (String, mlua::LuaString, Option<Table>)| async move {
                let write = Write::from_args(path, &data, opts.as_ref())?;
                let written = io::run(io::handle(&lua)?, write.run()).await?;
                io::settle(&lua, written.map(|()| true))
            },
        )?,
    )?;
    fs.set(
        "list",
        lua.create_async_function(|lua, path: String| async move {
            match io::run(io::handle(&lua)?, list(path)).await? {
                Ok(entries) => lua.to_value(&entries)?.into_lua_multi(&lua),
                Err(err) => io::failure(&lua, &err),
            }
        })?,
    )?;
    fs.set(
        "stat",
        lua.create_async_function(|lua, path: String| async move {
            match io::run(io::handle(&lua)?, tokio::fs::metadata(path)).await? {
                Ok(metadata) => lua.to_value(&stat_of(&metadata))?.into_lua_multi(&lua),
                Err(err) => io::failure(&lua, &err),
            }
        })?,
    )?;
    fs.set(
        "mkdir",
        lua.create_async_function(|lua, path: String| async move {
            let made = io::run(io::handle(&lua)?, tokio::fs::create_dir_all(path)).await?;
            io::settle(&lua, made.map(|()| true))
        })?,
    )?;
    fs.set(
        "remove",
        lua.create_async_function(|lua, (path, opts): (String, Option<Table>)| async move {
            let recursive = opts
                .map(|opts| opts.get::<Option<bool>>("recursive"))
                .transpose()?
                .flatten()
                .unwrap_or(false);
            let removed = io::run(io::handle(&lua)?, remove(path, recursive)).await?;
            io::settle(&lua, removed.map(|()| true))
        })?,
    )?;
    fs.set(
        "rename",
        lua.create_async_function(|lua, (from, to): (String, String)| async move {
            let renamed = io::run(io::handle(&lua)?, tokio::fs::rename(from, to)).await?;
            io::settle(&lua, renamed.map(|()| true))
        })?,
    )?;
    fs.set(
        "realpath",
        lua.create_async_function(|lua, path: String| async move {
            let resolved = io::run(io::handle(&lua)?, tokio::fs::canonicalize(path)).await?;
            io::settle(&lua, resolved.map(|path| path.display().to_string()))
        })?,
    )?;
    Ok(fs)
}

async fn remove(path: String, recursive: bool) -> std::io::Result<()> {
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
