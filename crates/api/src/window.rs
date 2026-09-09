use std::rc::Rc;

use mlua::{Function, Lua, LuaSerdeExt, Table, Value as LuaValue};

use crate::model::{Builtin, Color, Line, Size, Span, Style, UiConfig, WinOpts};

use super::Api;
use super::convert::FromLuaValue;

pub fn open_win(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, opts: Option<Table>| {
        let (builtin, win_opts) = match opts {
            Some(table) => {
                let builtin = match table.get::<Option<String>>("view")? {
                    Some(view) => Some(
                        view.parse::<Builtin>()
                            .map_err(|err| mlua::Error::runtime(err.to_string()))?,
                    ),
                    None => None,
                };
                (builtin, WinOpts::from_lua_value(&LuaValue::Table(table))?)
            }
            None => (None, WinOpts::default()),
        };
        let mut state = state.borrow_mut();
        Ok(state.open_window(builtin, win_opts))
    })
}

pub fn close_win(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, id: u32| {
        let mut state = state.borrow_mut();
        Ok(state.close_window(id))
    })
}

pub fn set_lines(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, (id, values): (u32, Table)| {
        let mut lines = Vec::new();
        for value in values.sequence_values::<LuaValue>() {
            lines.push(line_from_lua(value?)?);
        }
        state.borrow_mut().set_window_lines(id, lines);
        Ok(())
    })
}

pub fn clear(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, id: u32| {
        state.borrow_mut().clear_window(id);
        Ok(())
    })
}

pub fn set_size(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, (id, size): (u32, LuaValue)| {
        let size = Size::from_lua_value(&size)?;
        state.borrow_mut().set_window_size(id, size);
        Ok(())
    })
}

pub fn set_title(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |_, (id, title): (u32, Option<String>)| {
        state.borrow_mut().set_window_title(id, title);
        Ok(())
    })
}

pub fn configure(lua: &Lua, api: &Rc<Api>) -> mlua::Result<Function> {
    let state = api.state();
    lua.create_function(move |lua, opts: Table| {
        let config: UiConfig = lua.from_value(LuaValue::Table(opts))?;
        state.borrow_mut().apply_config(&config);
        Ok(())
    })
}

fn span_from_lua(value: LuaValue) -> mlua::Result<Span> {
    match value {
        LuaValue::String(s) => Ok(Span::new(s.to_str()?.to_owned())),
        LuaValue::Table(table) => {
            let text = table.get::<String>("text")?;
            let style = Style {
                fg: parse_color(table.get::<Option<String>>("color")?)?,
                bg: parse_color(table.get::<Option<String>>("bg")?)?,
                bold: table.get::<Option<bool>>("bold")?.unwrap_or(false),
                italic: table.get::<Option<bool>>("italic")?.unwrap_or(false),
                underline: table.get::<Option<bool>>("underline")?.unwrap_or(false),
            };
            Ok(Span::styled(text, style))
        }
        other => Err(mlua::Error::runtime(format!(
            "span must be a string or {{ text = .., color = .. }}, got {other:?}"
        ))),
    }
}

fn line_from_lua(value: LuaValue) -> mlua::Result<Line> {
    match &value {
        LuaValue::Table(table) if !table.contains_key("text")? => {
            let mut spans = Vec::new();
            for item in table.sequence_values::<LuaValue>() {
                spans.push(span_from_lua(item?)?);
            }
            Ok(Line { spans })
        }
        _ => Ok(Line::single(span_from_lua(value)?)),
    }
}

fn parse_color(value: Option<String>) -> mlua::Result<Option<Color>> {
    match value {
        Some(s) => s
            .parse::<Color>()
            .map(Some)
            .map_err(|err: crate::model::ParseError| mlua::Error::runtime(err.to_string())),
        None => Ok(None),
    }
}
