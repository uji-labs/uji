mod buffer;
mod command;
mod event;
mod llm;
mod schedule;
mod window;

use std::rc::Rc;

use mlua::{Function, Lua as LuaState, Table};

use crate::runtime::Inner;

struct Api {
    key: &'static str,
    build: fn(&LuaState, &Rc<Inner>) -> mlua::Result<Function>,
}

static UI_REGISTRY: &[Api] = &[
    Api {
        key: "create_buf",
        build: buffer::create_buf,
    },
    Api {
        key: "open_win",
        build: window::open_win,
    },
    Api {
        key: "close_win",
        build: window::close_win,
    },
];

static REGISTRY: &[Api] = &[
    Api {
        key: "schedule",
        build: schedule::schedule,
    },
    Api {
        key: "on",
        build: event::on,
    },
    Api {
        key: "emit",
        build: event::emit,
    },
    Api {
        key: "notify",
        build: event::notify,
    },
    Api {
        key: "command",
        build: command::command,
    },
];

pub(crate) fn register_all(lua: &LuaState, inner: &Rc<Inner>) -> mlua::Result<Table> {
    let uji = lua.create_table()?;

    let ui = lua.create_table()?;
    for entry in UI_REGISTRY {
        ui.set(entry.key, (entry.build)(lua, inner)?)?;
    }
    let opt = lua.create_table()?;
    opt.set("cursor_blink", true)?;
    ui.set("opt", opt)?;
    uji.set("ui", ui)?;

    let llm = lua.create_table()?;
    llm.set("current_provider", llm::current_provider(lua, inner)?)?;
    llm.set("current_model", llm::current_model(lua, inner)?)?;
    uji.set("llm", llm)?;

    for entry in REGISTRY {
        uji.set(entry.key, (entry.build)(lua, inner)?)?;
    }

    Ok(uji)
}
