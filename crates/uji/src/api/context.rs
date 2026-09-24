use std::rc::Rc;

use mlua::{Function, Lua, LuaSerdeExt, Table, Value};
use serde::Deserialize;
use uji_core::llm::Retention;
use uji_ui::config::overlay;

use crate::api::Api;
use crate::api::bind::bind;
use crate::api::registry::{DEFAULT_PRIORITY, Entry};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Compaction {
    pub enabled: bool,
    pub reserve: Option<u64>,
    pub keep_recent: u64,
}

impl Default for Compaction {
    fn default() -> Self {
        Self {
            enabled: true,
            reserve: None,
            keep_recent: 20_000,
        }
    }
}

#[derive(Deserialize, Default, Clone, Copy)]
#[serde(default, deny_unknown_fields)]
struct CompactionConfig {
    enabled: Option<bool>,
    reserve: Option<u64>,
    keep_recent: Option<u64>,
}

#[derive(Deserialize, Default)]
#[serde(default, deny_unknown_fields)]
struct ContextConfig {
    compaction: CompactionConfig,
    cache: Option<Retention>,
}

impl Compaction {
    fn apply(&mut self, config: CompactionConfig) {
        overlay(&mut self.enabled, config.enabled);
        overlay(&mut self.reserve, config.reserve.map(Some));
        overlay(&mut self.keep_recent, config.keep_recent);
    }
}

pub(crate) fn add(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(
        lua,
        api,
        move |api, _, (name, call, opts): (String, Function, Option<Table>)| {
            let priority = opts
                .map(|opts| opts.get::<Option<i64>>("priority"))
                .transpose()?
                .flatten()
                .unwrap_or(DEFAULT_PRIORITY);
            api.context().borrow_mut().add(Entry {
                name,
                priority,
                call,
            });
            Ok(())
        },
    )
}

pub(crate) fn remove(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, _, name: String| {
        Ok(api.context().borrow_mut().remove(&name))
    })
}

pub(crate) fn list(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, _, ()| {
        Ok(api.context().borrow().names())
    })
}

pub(crate) fn configure(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, lua, opts: Table| {
        let config: ContextConfig = lua.from_value(Value::Table(opts))?;
        api.compaction().borrow_mut().apply(config.compaction);
        if let Some(cache) = config.cache {
            api.cache().set(cache);
        }
        Ok(())
    })
}

pub(crate) fn register(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Table> {
    let context = lua.create_table()?;
    context.set("add", add(lua, api)?)?;
    context.set("remove", remove(lua, api)?)?;
    context.set("list", list(lua, api)?)?;
    context.set("configure", configure(lua, api)?)?;
    Ok(context)
}
