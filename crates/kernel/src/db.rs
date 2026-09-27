use mlua::{Function, Lua, LuaSerdeExt, MultiValue, Table, UserData, UserDataMethods, Value};
use rusqlite::types::{Value as SqlValue, ValueRef};
use rusqlite::{Connection, params_from_iter};

use crate::io;

pub(crate) struct Db(Option<Connection>);

impl Db {
    fn connection(&self) -> mlua::Result<&Connection> {
        self.0
            .as_ref()
            .ok_or_else(|| mlua::Error::runtime("the database is closed"))
    }
}

fn sql_value(value: Value) -> mlua::Result<SqlValue> {
    Ok(match value {
        Value::Nil => SqlValue::Null,
        Value::LightUserData(data) if data.0.is_null() => SqlValue::Null,
        Value::Boolean(flag) => SqlValue::Integer(i64::from(flag)),
        Value::Integer(number) => SqlValue::Integer(number),
        Value::Number(number) => SqlValue::Real(number),
        Value::String(text) => match text.to_str() {
            Ok(text) => SqlValue::Text(text.to_string()),
            Err(_) => SqlValue::Blob(text.as_bytes().to_vec()),
        },
        other => {
            return Err(mlua::Error::runtime(format!(
                "a {} cannot be stored in the database",
                other.type_name()
            )));
        }
    })
}

fn sql_values(params: Option<Vec<Value>>) -> mlua::Result<Vec<SqlValue>> {
    params
        .unwrap_or_default()
        .into_iter()
        .map(sql_value)
        .collect()
}

fn lua_value(lua: &Lua, value: ValueRef<'_>) -> mlua::Result<Value> {
    Ok(match value {
        ValueRef::Null => Value::Nil,
        ValueRef::Integer(number) => Value::Integer(number),
        ValueRef::Real(number) => Value::Number(number),
        ValueRef::Text(bytes) | ValueRef::Blob(bytes) => Value::String(lua.create_string(bytes)?),
    })
}

fn row(lua: &Lua, columns: &[String], row: &rusqlite::Row<'_>) -> mlua::Result<Table> {
    let table = lua.create_table()?;
    for (index, name) in columns.iter().enumerate() {
        let value = row.get_ref(index).map_err(mlua::Error::external)?;
        table.raw_set(name.as_str(), lua_value(lua, value)?)?;
    }
    Ok(table)
}

fn query(
    lua: &Lua,
    connection: &Connection,
    sql: &str,
    params: Option<Vec<Value>>,
) -> mlua::Result<Table> {
    let mut statement = connection
        .prepare_cached(sql)
        .map_err(mlua::Error::external)?;
    let columns: Vec<String> = statement
        .column_names()
        .into_iter()
        .map(str::to_string)
        .collect();
    let mut rows = statement
        .query(params_from_iter(sql_values(params)?))
        .map_err(mlua::Error::external)?;
    let out = lua.create_table()?;
    while let Some(found) = rows.next().map_err(mlua::Error::external)? {
        out.raw_push(row(lua, &columns, found)?)?;
    }
    Ok(out)
}

fn exec(connection: &Connection, sql: &str, params: Option<Vec<Value>>) -> mlua::Result<usize> {
    let Some(params) = params else {
        return connection
            .execute_batch(sql)
            .map(|()| 0)
            .map_err(mlua::Error::external);
    };
    let values = sql_values(Some(params))?;
    connection
        .prepare_cached(sql)
        .and_then(|mut statement| statement.execute(params_from_iter(values)))
        .map_err(mlua::Error::external)
}

fn transaction(connection: &Connection, run: &Function) -> mlua::Result<MultiValue> {
    connection
        .execute_batch("BEGIN")
        .map_err(mlua::Error::external)?;
    match run.call::<MultiValue>(()) {
        Ok(values) => connection
            .execute_batch("COMMIT")
            .map(|()| values)
            .map_err(mlua::Error::external),
        Err(err) => {
            connection
                .execute_batch("ROLLBACK")
                .map_err(mlua::Error::external)?;
            Err(err)
        }
    }
}

impl UserData for Db {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method(
            "exec",
            |_, db, (sql, params): (String, Option<Vec<Value>>)| {
                exec(db.connection()?, &sql, params)
            },
        );
        methods.add_method(
            "query",
            |lua, db, (sql, params): (String, Option<Vec<Value>>)| {
                query(lua, db.connection()?, &sql, params)
            },
        );
        methods.add_method("transaction", |_, db, run: Function| {
            transaction(db.connection()?, &run)
        });
        methods.add_method_mut("close", |_, db, ()| {
            db.0.take();
            Ok(())
        });
    }
}

pub(crate) fn register(lua: &Lua) -> mlua::Result<Table> {
    let db = lua.create_table()?;
    db.set(
        "open",
        lua.create_function(|lua, path: String| {
            io::settle(
                lua,
                Connection::open(path).map(|connection| Db(Some(connection))),
            )
        })?,
    )?;
    db.set("null", lua.null())?;
    Ok(db)
}
