use std::borrow::Cow;
use std::ops::Range;

use mlua::{Lua, Table};
use pulldown_cmark::{CodeBlockKind, Event, HeadingLevel, Options, Parser, Tag, TagEnd};
use uji_macros::function;

use crate::utils::lua::stack::{self, Stack};

const EXTENSIONS: Options = Options::ENABLE_STRIKETHROUGH
    .union(Options::ENABLE_TABLES)
    .union(Options::ENABLE_TASKLISTS)
    .union(Options::ENABLE_MATH);

const BRACKETS: [(&str, &str, &str, &str); 2] =
    [("\\(", "\\)", "${", "}$"), ("\\[", "\\]", "$$", "$$")];

enum Field<'a> {
    Nil,
    Text(&'a str),
    Integer(i64),
    Flag(bool),
}

impl Field<'_> {
    fn push(&self, stack: &Stack) {
        match *self {
            Field::Nil => stack.nil(),
            Field::Text(text) => stack.string(text),
            Field::Integer(value) => stack.integer(value),
            Field::Flag(value) => stack.boolean(value),
        }
    }
}

fn name(tag: TagEnd) -> &'static str {
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

fn detail<'a>(tag: &'a Tag<'_>) -> Field<'a> {
    match tag {
        Tag::Heading { level: at, .. } => Field::Integer(level(*at)),
        Tag::CodeBlock(CodeBlockKind::Fenced(language)) => Field::Text(language),
        Tag::List(start) => start
            .and_then(|start| i64::try_from(start).ok())
            .map_or(Field::Nil, Field::Integer),
        Tag::Link { dest_url, .. } | Tag::Image { dest_url, .. } => Field::Text(dest_url),
        _ => Field::Nil,
    }
}

fn describe<'a>(event: &'a Event<'_>) -> Option<(&'a str, Field<'a>, Field<'a>)> {
    let described = match event {
        Event::Start(tag) => ("start", Field::Text(name(tag.to_end())), detail(tag)),
        Event::End(tag) => ("end", Field::Text(name(*tag)), Field::Nil),
        Event::Text(body) => ("text", Field::Text(body), Field::Nil),
        Event::Code(body) => ("code", Field::Text(body), Field::Nil),
        Event::Html(body) | Event::InlineHtml(body) => ("html", Field::Text(body), Field::Nil),
        Event::InlineMath(body) => ("math", Field::Text(body), Field::Flag(false)),
        Event::DisplayMath(body) => ("math", Field::Text(body), Field::Flag(true)),
        Event::SoftBreak => ("break", Field::Text("soft"), Field::Nil),
        Event::HardBreak => ("break", Field::Text("hard"), Field::Nil),
        Event::Rule => ("rule", Field::Nil, Field::Nil),
        Event::TaskListMarker(done) => ("task", Field::Flag(*done), Field::Nil),
        Event::FootnoteReference(_) => return None,
    };
    Some(described)
}

fn code(source: &str) -> Vec<Range<usize>> {
    Parser::new_ext(source, EXTENSIONS)
        .into_offset_iter()
        .filter(|(event, _)| {
            matches!(
                event,
                Event::Start(Tag::CodeBlock(_))
                    | Event::Code(_)
                    | Event::Html(_)
                    | Event::InlineHtml(_)
            )
        })
        .map(|(_, range)| range)
        .collect()
}

fn find(text: &str, needle: &str, from: usize, code: &[Range<usize>]) -> Option<usize> {
    text[from..]
        .match_indices(needle)
        .map(|(at, _)| from + at)
        .find(|&at| !text[..at].ends_with('\\') && !code.iter().any(|range| range.contains(&at)))
}

fn dollar_math(source: &str) -> Cow<'_, str> {
    if !BRACKETS.iter().any(|(open, ..)| source.contains(open)) {
        return Cow::Borrowed(source);
    }
    let code = code(source);
    let mut out = source.to_owned();
    for (open, close, dollar_open, dollar_close) in BRACKETS {
        let mut from = 0;
        while let Some(start) = find(&out, open, from, &code)
            && let Some(end) = find(&out, close, start + open.len(), &code)
        {
            out.replace_range(start..start + open.len(), dollar_open);
            out.replace_range(end..end + close.len(), dollar_close);
            from = end + close.len();
        }
    }
    Cow::Owned(out)
}

fn position(offset: usize) -> Field<'static> {
    Field::Integer(i64::try_from(offset).unwrap_or(i64::MAX))
}

fn list(stack: &Stack, fields: &[Field<'_>]) {
    stack.table(fields.len());
    for (index, field) in (1..).zip(fields) {
        field.push(stack);
        stack.set_index(index);
    }
}

#[function]
fn markdown(lua: &Lua, source: &str) -> mlua::Result<Table> {
    let source = dollar_math(source);
    stack::build(lua, (), |stack| {
        stack.table(0);
        let mut length = 0;
        for (event, range) in Parser::new_ext(&source, EXTENSIONS).into_offset_iter() {
            let Some((kind, first, second)) = describe(&event) else {
                continue;
            };
            let start = position(range.start + 1);
            let end = position(range.end);
            list(stack, &[Field::Text(kind), first, second, start, end]);
            length += 1;
            stack.set_index(length);
        }
        Ok(())
    })
}
