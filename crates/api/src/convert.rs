use crate::model::{Border, Color, Size, Split, WinOpts};
use mlua::Value as LuaValue;

pub(crate) trait FromLuaValue: Sized {
    fn from_lua_value(value: &LuaValue) -> mlua::Result<Self>;
}

impl FromLuaValue for Size {
    fn from_lua_value(value: &LuaValue) -> mlua::Result<Self> {
        match value {
            LuaValue::Integer(n) => u16::try_from(*n)
                .map(Size::from)
                .map_err(|_| mlua::Error::runtime("size must fit in u16")),
            LuaValue::String(s) => s
                .to_str()?
                .parse::<Size>()
                .map_err(|err| mlua::Error::runtime(err.to_string())),
            _ => Err(mlua::Error::runtime("size must be a number or \"fill\"")),
        }
    }
}

impl FromLuaValue for WinOpts {
    fn from_lua_value(value: &LuaValue) -> mlua::Result<Self> {
        let LuaValue::Table(table) = value else {
            return Err(mlua::Error::runtime("window options must be a table"));
        };
        let mut opts = WinOpts::default();
        if let Some(split) = table.get::<Option<String>>("split")? {
            opts.split = split
                .parse::<Split>()
                .map_err(|err| mlua::Error::runtime(err.to_string()))?;
        }
        if let Some(size) = table.get::<Option<LuaValue>>("size")? {
            opts.size = Size::from_lua_value(&size)?;
        }
        if let Some(border) = table.get::<Option<String>>("border")? {
            opts.border = border
                .parse::<Border>()
                .map_err(|err| mlua::Error::runtime(err.to_string()))?;
        }
        opts.title = table.get::<Option<String>>("title")?;
        opts.wrap = table.get::<Option<bool>>("wrap")?.unwrap_or(false);
        opts.padding = table.get::<Option<u16>>("padding")?.unwrap_or(0);
        if let Some(color) = table.get::<Option<String>>("border_color")? {
            opts.border_color = Some(
                color
                    .parse::<Color>()
                    .map_err(|err| mlua::Error::runtime(err.to_string()))?,
            );
        }
        Ok(opts)
    }
}
