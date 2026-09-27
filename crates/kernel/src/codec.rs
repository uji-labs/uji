use base64::Engine;
use base64::engine::GeneralPurpose;
use base64::engine::general_purpose::{STANDARD, STANDARD_NO_PAD, URL_SAFE, URL_SAFE_NO_PAD};
use std::ops::Range;

use mlua::serde::SerializeOptions;
use mlua::{Lua, LuaSerdeExt, Table, Value};
use pulldown_cmark::{
    CodeBlockKind, Event, HeadingLevel, Options as Extensions, Parser, Tag, TagEnd,
};
use rand::RngCore;
use sha2::{Digest, Sha256};
use unicode_width::UnicodeWidthStr;

fn json(lua: &Lua) -> mlua::Result<Table> {
    let json = lua.create_table()?;
    json.set(
        "encode",
        lua.create_function(|_, value: Value| {
            serde_json::to_string(&value).map_err(mlua::Error::external)
        })?,
    )?;
    json.set(
        "decode",
        lua.create_function(|lua, (text, opts): (mlua::LuaString, Option<Table>)| {
            let value: serde_json::Value =
                serde_json::from_slice(&text.as_bytes()).map_err(mlua::Error::external)?;
            let nulls = opts
                .map(|opts| opts.get::<Option<bool>>("nulls"))
                .transpose()?
                .flatten()
                .unwrap_or(true);
            let options = SerializeOptions::new()
                .serialize_none_to_null(nulls)
                .serialize_unit_to_null(nulls);
            lua.to_value_with(&value, options)
        })?,
    )?;
    json.set(
        "array",
        lua.create_function(|lua, table: Table| {
            table.set_metatable(Some(lua.array_metatable()))?;
            Ok(table)
        })?,
    )?;
    json.set("null", lua.null())?;
    Ok(json)
}

fn engine(opts: Option<&Table>) -> mlua::Result<&'static GeneralPurpose> {
    let flag = |key: &str, default: bool| -> mlua::Result<bool> {
        Ok(opts
            .map(|opts| opts.get::<Option<bool>>(key))
            .transpose()?
            .flatten()
            .unwrap_or(default))
    };
    Ok(match (flag("url", false)?, flag("pad", true)?) {
        (false, true) => &STANDARD,
        (false, false) => &STANDARD_NO_PAD,
        (true, true) => &URL_SAFE,
        (true, false) => &URL_SAFE_NO_PAD,
    })
}

fn base64(lua: &Lua) -> mlua::Result<Table> {
    let base64 = lua.create_table()?;
    base64.set(
        "encode",
        lua.create_function(|_, (data, opts): (mlua::LuaString, Option<Table>)| {
            Ok(engine(opts.as_ref())?.encode(data.as_bytes()))
        })?,
    )?;
    base64.set(
        "decode",
        lua.create_function(|lua, (text, opts): (mlua::LuaString, Option<Table>)| {
            let bytes = engine(opts.as_ref())?
                .decode(text.as_bytes())
                .map_err(mlua::Error::external)?;
            lua.create_string(bytes)
        })?,
    )?;
    Ok(base64)
}

fn level(level: HeadingLevel) -> i64 {
    match level {
        HeadingLevel::H1 => 1,
        HeadingLevel::H2 => 2,
        HeadingLevel::H3 => 3,
        HeadingLevel::H4 => 4,
        HeadingLevel::H5 => 5,
        HeadingLevel::H6 => 6,
    }
}

fn opened(lua: &Lua, tag: &Tag<'_>) -> mlua::Result<(&'static str, Value)> {
    let text = |text: &str| lua.create_string(text).map(Value::String);
    Ok(match tag {
        Tag::Paragraph => ("paragraph", Value::Nil),
        Tag::Heading { level: at, .. } => ("heading", Value::Integer(level(*at))),
        Tag::BlockQuote(_) => ("blockquote", Value::Nil),
        Tag::CodeBlock(CodeBlockKind::Fenced(language)) => ("code_block", text(language)?),
        Tag::CodeBlock(CodeBlockKind::Indented) => ("code_block", Value::Nil),
        Tag::List(start) => (
            "list",
            start
                .and_then(|start| i64::try_from(start).ok())
                .map_or(Value::Nil, Value::Integer),
        ),
        Tag::Item => ("item", Value::Nil),
        Tag::Emphasis => ("emphasis", Value::Nil),
        Tag::Strong => ("strong", Value::Nil),
        Tag::Strikethrough => ("strikethrough", Value::Nil),
        Tag::Link { dest_url, .. } => ("link", text(dest_url)?),
        Tag::Image { dest_url, .. } => ("image", text(dest_url)?),
        Tag::Table(_) => ("table", Value::Nil),
        Tag::TableHead => ("table_head", Value::Nil),
        Tag::TableRow => ("table_row", Value::Nil),
        Tag::TableCell => ("table_cell", Value::Nil),
        _ => ("other", Value::Nil),
    })
}

fn closed(tag: TagEnd) -> &'static str {
    match tag {
        TagEnd::Paragraph => "paragraph",
        TagEnd::Heading(_) => "heading",
        TagEnd::BlockQuote(_) => "blockquote",
        TagEnd::CodeBlock => "code_block",
        TagEnd::List(_) => "list",
        TagEnd::Item => "item",
        TagEnd::Emphasis => "emphasis",
        TagEnd::Strong => "strong",
        TagEnd::Strikethrough => "strikethrough",
        TagEnd::Link => "link",
        TagEnd::Image => "image",
        TagEnd::Table => "table",
        TagEnd::TableHead => "table_head",
        TagEnd::TableRow => "table_row",
        TagEnd::TableCell => "table_cell",
        _ => "other",
    }
}

fn event(lua: &Lua, event: Event<'_>, range: Range<usize>) -> mlua::Result<Option<Table>> {
    let entry = |kind: &str, first: Value, second: Value| -> mlua::Result<Option<Table>> {
        let table = lua.create_table()?;
        table.raw_set(1, kind)?;
        table.raw_set(2, first)?;
        table.raw_set(3, second)?;
        table.raw_set(4, range.start.saturating_add(1))?;
        table.raw_set(5, range.end)?;
        Ok(Some(table))
    };
    let text = |text: &str| lua.create_string(text).map(Value::String);
    match event {
        Event::Start(tag) => {
            let (name, detail) = opened(lua, &tag)?;
            entry("start", text(name)?, detail)
        }
        Event::End(tag) => entry("end", text(closed(tag))?, Value::Nil),
        Event::Text(body) => entry("text", text(&body)?, Value::Nil),
        Event::Code(body) => entry("code", text(&body)?, Value::Nil),
        Event::Html(body) | Event::InlineHtml(body) => entry("html", text(&body)?, Value::Nil),
        Event::SoftBreak => entry("break", text("soft")?, Value::Nil),
        Event::HardBreak => entry("break", text("hard")?, Value::Nil),
        Event::Rule => entry("rule", Value::Nil, Value::Nil),
        Event::TaskListMarker(done) => entry("task", Value::Boolean(done), Value::Nil),
        _ => Ok(None),
    }
}

fn markdown(lua: &Lua, source: &str) -> mlua::Result<Table> {
    let mut extensions = Extensions::empty();
    extensions.insert(Extensions::ENABLE_STRIKETHROUGH);
    extensions.insert(Extensions::ENABLE_TABLES);
    extensions.insert(Extensions::ENABLE_TASKLISTS);
    let events = lua.create_table()?;
    for (parsed, range) in Parser::new_ext(source, extensions).into_offset_iter() {
        if let Some(table) = event(lua, parsed, range)? {
            events.raw_push(table)?;
        }
    }
    Ok(events)
}

pub(crate) fn install(lua: &Lua, uji: &Table) -> mlua::Result<()> {
    uji.set("json", json(lua)?)?;
    uji.set("base64", base64(lua)?)?;
    uji.set(
        "sha256",
        lua.create_function(|lua, data: mlua::LuaString| {
            lua.create_string(Sha256::digest(data.as_bytes()))
        })?,
    )?;
    uji.set(
        "random",
        lua.create_function(|lua, count: usize| {
            let mut bytes = vec![0; count];
            rand::rng().fill_bytes(&mut bytes);
            lua.create_string(bytes)
        })?,
    )?;
    uji.set(
        "lossy",
        lua.create_function(|_, data: mlua::LuaString| Ok(data.to_string_lossy()))?,
    )?;
    uji.set(
        "width",
        lua.create_function(|_, text: mlua::LuaString| Ok(text.to_string_lossy().width()))?,
    )?;
    uji.set(
        "markdown",
        lua.create_function(|lua, source: mlua::LuaString| {
            markdown(lua, &source.to_string_lossy())
        })?,
    )?;
    Ok(())
}
