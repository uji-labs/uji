use arboard::Clipboard;
use mlua::{Lua, Table};

use crate::io;
use crate::kernel::State;

fn open(slot: &mut Option<Clipboard>) -> Result<&mut Clipboard, arboard::Error> {
    if slot.is_none() {
        *slot = Some(Clipboard::new()?);
    }
    slot.as_mut().ok_or(arboard::Error::ClipboardNotSupported)
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let clipboard = lua.create_table()?;
    clipboard.set(
        "get",
        lua.create_function(|lua, ()| {
            let read = open(&mut State::of_mut(lua)?.clipboard).and_then(Clipboard::get_text);
            io::settle(lua, read)
        })?,
    )?;
    clipboard.set(
        "set",
        lua.create_function(|lua, text: String| {
            let copied = open(&mut State::of_mut(lua)?.clipboard)
                .and_then(|clipboard| clipboard.set_text(text));
            io::settle(lua, copied.map(|()| true))
        })?,
    )?;
    Ok(clipboard)
}
