use std::rc::Rc;

use mlua::{Function, Lua, Table, Value};

use crate::api::Api;
use crate::api::bind::bind;
use crate::api::registry::Entry;
use uji_ui::model::RunState;

pub fn add(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(
        lua,
        api,
        move |api, _, (name, render, opts): (String, Function, Option<Table>)| {
            let priority = opts
                .map(|opts| opts.get::<Option<i64>>("priority"))
                .transpose()?
                .flatten()
                .unwrap_or(50);
            api.segments().borrow_mut().add(Entry {
                name,
                priority,
                call: render,
            });
            Ok(())
        },
    )
}

pub fn remove(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, _, name: String| {
        api.segments().borrow_mut().remove(&name);
        Ok(())
    })
}

/// Calls every registered segment and returns the ones that produced something.
pub fn segments(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, lua, ()| {
        let out = lua.create_table()?;
        for (name, render) in api.segments().borrow().calls() {
            match render.call::<Value>(()) {
                Ok(Value::Nil) => {}
                Ok(value) => out.push(value)?,
                Err(err) => {
                    api.notify(format!("status segment {name}: {err}"));
                }
            }
        }
        Ok(out)
    })
}

pub fn provider(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, ()| Ok(state.borrow().current_provider().map(str::to_string)))
}

pub fn model(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, ()| Ok(state.borrow().current_model().map(str::to_string)))
}

pub fn effort(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, ()| Ok(state.borrow().current_effort().map(str::to_string)))
}

pub fn queue(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |lua, ()| {
        let out = lua.create_table()?;
        for text in state.borrow().queued() {
            out.push(text.clone())?;
        }
        Ok(out)
    })
}

pub fn context(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, lua, ()| {
        let out = lua.create_table()?;
        out.set("used", api.session().conversation().borrow().used_tokens())?;
        if let Some(window) = api.state().borrow().context_window() {
            out.set("window", window)?;
        }
        Ok(out)
    })
}

pub fn state(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, ()| {
        Ok(match state.borrow().run_state() {
            RunState::Idle => "idle",
            RunState::Working => "working",
            RunState::Error => "error",
        })
    })
}

pub fn elapsed(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, ()| {
        Ok(state
            .borrow()
            .turn_started()
            .map(|started| started.elapsed().as_secs_f64()))
    })
}

pub fn loader_frame(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, ()| Ok(state.borrow().loader_frame()))
}
