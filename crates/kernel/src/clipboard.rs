use arboard::Clipboard;
use mlua::{Lua, Table};

use crate::io;

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let clipboard = lua.create_table()?;
    clipboard.set(
        "get",
        lua.create_function(|lua, ()| {
            io::settle(
                lua,
                Clipboard::new().and_then(|mut clipboard| clipboard.get_text()),
            )
        })?,
    )?;
    clipboard.set(
        "set",
        lua.create_function(|lua, text: String| {
            let copied = Clipboard::new().and_then(|mut clipboard| clipboard.set_text(text));
            io::settle(lua, copied.map(|()| true))
        })?,
    )?;
    Ok(clipboard)
}
