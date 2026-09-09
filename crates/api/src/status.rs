use std::rc::Rc;

use mlua::{Function, Lua};

use crate::Api;
use crate::model::{LoaderMode, RunState};

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
    lua.create_function(move |_, ()| {
        let state = state.borrow();
        let Some(started) = state.turn_started() else {
            return Ok(String::new());
        };
        let frames: &[&str] = match state.opts().waiting.loader_mode {
            LoaderMode::Braille => &["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
            LoaderMode::Dots => &["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"],
            LoaderMode::Line => &["|", "/", "-", "\\"],
            LoaderMode::Pulse => &["●", "○"],
            LoaderMode::None => return Ok(String::new()),
        };
        let interval = u128::from(state.opts().waiting.loader_interval_ms.max(1));
        let len = u128::try_from(frames.len()).unwrap_or(1);
        let idx = (started.elapsed().as_millis() / interval) % len;
        let idx = usize::try_from(idx).unwrap_or(0);
        Ok(frames[idx].to_string())
    })
}

pub fn set_status(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, line: String| {
        state.borrow_mut().set_status(line);
        Ok(())
    })
}
