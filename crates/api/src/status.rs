use std::rc::Rc;

use mlua::{Function, Lua};

use crate::Api;
use crate::model::RunState;

pub fn footer_clear(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, ()| {
        state.borrow_mut().clear_footer();
        Ok(())
    })
}

pub fn footer_push(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, segment: String| {
        state.borrow_mut().push_footer(segment);
        Ok(())
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
