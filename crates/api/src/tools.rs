use std::rc::Rc;

use mlua::{Function, Lua, Table, Value as LuaValue};

use super::Api;

#[derive(Debug, Clone)]
pub struct LuaTool {
    pub description: String,
    pub parameters: LuaValue,
    pub subject: Option<String>,
    pub run: Function,
}

pub fn register(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let api = api.clone();
    lua.create_function(move |_, (name, opts): (String, Table)| {
        let description = opts
            .get::<Option<String>>("description")?
            .unwrap_or_default();
        let parameters = opts.get::<LuaValue>("parameters")?;
        let subject = opts.get::<Option<String>>("subject")?;
        let run: Function = opts.get("run")?;
        api.lua_tools().borrow_mut().insert(
            name,
            LuaTool {
                description,
                parameters,
                subject,
                run,
            },
        );
        Ok(())
    })
}

pub fn unregister(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let api = api.clone();
    lua.create_function(move |_, name: String| {
        api.lua_tools().borrow_mut().remove(&name);
        Ok(())
    })
}
