use std::rc::Rc;

use mlua::{Function, Lua, Table};

use crate::api::handlers::{DEFAULT_PRIORITY, Handler};

use super::Api;
use crate::api::bind::bind;

pub fn on(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(
        lua,
        api,
        move |api, _, (event, call, opts): (String, Function, Option<Table>)| {
            let (priority, named) = match opts {
                Some(opts) => (
                    opts.get::<Option<i64>>("priority")?,
                    opts.get::<Option<String>>("name")?,
                ),
                None => (None, None),
            };
            let mut handlers = api.handlers().borrow_mut();
            let name = match named {
                Some(name) => name,
                None => handlers.anonymous(),
            };
            handlers.add(
                event,
                Handler {
                    name: name.clone(),
                    priority: priority.unwrap_or(DEFAULT_PRIORITY),
                    call,
                },
            );
            Ok(name)
        },
    )
}

pub fn off(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, _, (event, name): (String, String)| {
        Ok(api.handlers().borrow_mut().remove(&event, &name))
    })
}

pub fn emit(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, _, (event, ctx): (String, Table)| {
        api.dispatch(&event, &ctx);
        Ok(())
    })
}

pub fn notify(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    bind(lua, api, move |api, _, message: String| {
        api.notify(message);
        Ok(())
    })
}
