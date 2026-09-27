use keyring::Entry;
use mlua::{IntoLuaMulti, Lua, MultiValue, Table};

use crate::io;

fn found(lua: &Lua, secret: Result<String, keyring::Error>) -> mlua::Result<MultiValue> {
    match secret {
        Ok(secret) => secret.into_lua_multi(lua),
        Err(keyring::Error::NoEntry) => Ok(MultiValue::new()),
        Err(err) => io::failure(lua, &err),
    }
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let keychain = lua.create_table()?;
    keychain.set(
        "get",
        lua.create_async_function(|lua, (service, account): (String, String)| async move {
            let secret = io::blocking(io::handle(&lua)?, move || {
                Entry::new(&service, &account).and_then(|entry| entry.get_password())
            })
            .await?;
            found(&lua, secret)
        })?,
    )?;
    keychain.set(
        "set",
        lua.create_async_function(
            |lua, (service, account, secret): (String, String, String)| async move {
                let stored = io::blocking(io::handle(&lua)?, move || {
                    Entry::new(&service, &account).and_then(|entry| entry.set_password(&secret))
                })
                .await?;
                io::settle(&lua, stored.map(|()| true))
            },
        )?,
    )?;
    keychain.set(
        "delete",
        lua.create_async_function(|lua, (service, account): (String, String)| async move {
            let deleted = io::blocking(io::handle(&lua)?, move || {
                Entry::new(&service, &account).and_then(|entry| entry.delete_credential())
            })
            .await?;
            io::settle(&lua, deleted.map(|()| true))
        })?,
    )?;
    Ok(keychain)
}
