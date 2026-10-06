use std::borrow::Cow;
use std::collections::BTreeSet;
use std::env::consts::DLL_EXTENSION;
use std::path::PathBuf;

use mlua::{FromLua, IntoLuaMulti, Lua, LuaOptions, MultiValue, StdLib, Table, Value};
use uji_macros::function;

use crate::kernel::State;

const AFTER_PRELOAD: i64 = 2;
const LUA_DIR: &str = "lua";
const NATIVE_DIR: &str = "native";
const NAMESPACE: &str = "uji.sys.";
const MACHINE_CODE: (&str, &str, &str) = ("sizemcode=16384", "maxmcode=65536", "maxtrace=8000");

pub(crate) struct Export {
    pub(crate) module: &'static str,
    pub(crate) name: Option<&'static str>,
    pub(crate) build: fn(&Lua) -> mlua::Result<Value>,
}

#[allow(unsafe_code)]
#[linkme::distributed_slice]
pub(crate) static EXPORTS: [Export];

#[derive(Clone)]
pub enum Sources {
    Embedded(&'static [(&'static str, &'static str)]),
    Directory(PathBuf),
}

impl Sources {
    fn find(&self, files: &[String]) -> Option<(String, Cow<'_, [u8]>)> {
        files
            .iter()
            .find_map(|file| self.read(file).map(|source| (self.name(file), source)))
    }

    fn read(&self, file: &str) -> Option<Cow<'_, [u8]>> {
        match self {
            Self::Embedded(files) => files
                .iter()
                .find(|(name, _)| *name == file)
                .map(|(_, source)| Cow::Borrowed(source.as_bytes())),
            Self::Directory(root) => std::fs::read(root.join(file)).ok().map(Cow::Owned),
        }
    }

    fn children(&self, namespace: &str) -> Vec<String> {
        let dir = namespace.replace('.', "/");
        match self {
            Self::Embedded(files) => files
                .iter()
                .filter_map(|(file, _)| file.strip_prefix(dir.as_str())?.strip_prefix('/'))
                .filter_map(child)
                .collect(),
            Self::Directory(root) => std::fs::read_dir(root.join(&dir))
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .filter_map(|entry| {
                    let name = entry.file_name().into_string().ok()?;
                    if entry.path().join("init.lua").is_file() {
                        Some(name)
                    } else {
                        child(&name)
                    }
                })
                .collect(),
        }
    }

    fn name(&self, file: &str) -> String {
        match self {
            Self::Embedded(_) => file.to_string(),
            Self::Directory(root) => root.join(file).display().to_string(),
        }
    }
}

fn candidates(module: &str) -> [String; 2] {
    let relative = module.replace('.', "/");
    [format!("{relative}.lua"), format!("{relative}/init.lua")]
}

fn child(rest: &str) -> Option<String> {
    let name = rest
        .strip_suffix("/init.lua")
        .or_else(|| rest.strip_suffix(".lua"))?;
    (name != "init" && !name.contains('/')).then(|| name.to_string())
}

#[allow(unsafe_code)]
fn lua(debug: bool) -> Lua {
    let libraries = if debug {
        StdLib::ALL_SAFE | StdLib::DEBUG
    } else {
        StdLib::ALL_SAFE
    };
    unsafe { Lua::unsafe_new_with(libraries, LuaOptions::new()) }
}

pub(crate) fn layers(sources: &[Sources], roots: &[PathBuf]) -> Vec<Sources> {
    roots
        .iter()
        .map(|root| Sources::Directory(root.join(LUA_DIR)))
        .chain(sources.iter().cloned())
        .collect()
}

fn natives(roots: &[PathBuf]) -> String {
    roots
        .iter()
        .map(|root| {
            root.join(NATIVE_DIR)
                .join(format!("?.{DLL_EXTENSION}"))
                .display()
                .to_string()
        })
        .collect::<Vec<_>>()
        .join(";")
}

pub(crate) fn create(layers: Vec<Sources>, roots: &[PathBuf], debug: bool) -> mlua::Result<Lua> {
    let lua = lua(debug);
    lua.globals()
        .get::<Table>("jit")?
        .get::<Table>("opt")?
        .get::<mlua::Function>("start")?
        .call::<()>(MACHINE_CODE)?;
    let package: Table = lua.globals().get("package")?;
    package.set("path", "")?;
    package.set("cpath", natives(roots))?;
    package
        .get::<Table>("preload")?
        .set("ito", lua.create_function(|lua, ()| ito::load(lua))?)?;
    let searchers: Table = package.get("searchers")?;
    searchers.raw_insert(
        AFTER_PRELOAD,
        lua.create_function(move |lua, module: String| written(lua, &layers, &module))?,
    )?;
    searchers.raw_push(lua.create_function(|lua, module: String| built_in(lua, &module))?)?;
    Ok(lua)
}

pub(crate) fn require<T: FromLua>(lua: &Lua, module: &str) -> mlua::Result<T> {
    lua.globals().get::<mlua::Function>("require")?.call(module)
}

fn written(lua: &Lua, layers: &[Sources], module: &str) -> mlua::Result<MultiValue> {
    let files = candidates(module);
    let Some((name, source)) = layers.iter().find_map(|layer| layer.find(&files)) else {
        return format!("\n\tno runtime module '{module}'").into_lua_multi(lua);
    };
    let chunk = lua
        .load(source.as_ref())
        .set_name(format!("@{name}"))
        .into_function()?;
    (chunk, name).into_lua_multi(lua)
}

fn built_in(lua: &Lua, module: &str) -> mlua::Result<MultiValue> {
    let exports: Vec<&Export> = module
        .strip_prefix(NAMESPACE)
        .map(|name| {
            EXPORTS
                .iter()
                .filter(|export| export.module == name)
                .collect()
        })
        .unwrap_or_default();
    if exports.is_empty() {
        return format!("\n\tno built-in module '{module}'").into_lua_multi(lua);
    }
    lua.create_function(move |lua, ()| open(lua, &exports))?
        .into_lua_multi(lua)
}

fn open(lua: &Lua, exports: &[&Export]) -> mlua::Result<Value> {
    if let [only] = exports
        && only.name.is_none()
    {
        return (only.build)(lua);
    }
    let table = lua.create_table()?;
    for export in exports {
        table.raw_set(export.name.unwrap_or(export.module), (export.build)(lua)?)?;
    }
    Ok(Value::Table(table))
}

#[function]
fn modules(state: &State, namespace: &str) -> Vec<String> {
    let names: BTreeSet<String> = state
        .layers
        .iter()
        .flat_map(|layer| layer.children(namespace))
        .collect();
    names
        .into_iter()
        .map(|name| format!("{namespace}.{name}"))
        .collect()
}
