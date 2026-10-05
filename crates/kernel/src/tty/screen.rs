use std::collections::HashMap;
use std::io;

use mlua::{Function, Value};
use ratatui::buffer::Buffer;
use ratatui::layout::{Position, Rect};
use ratatui::style::{Color, Modifier, Style};
use uji_macros::{methods, options};

const MODIFIERS: [(&str, Modifier); 7] = [
    ("bold", Modifier::BOLD),
    ("blink", Modifier::SLOW_BLINK),
    ("dim", Modifier::DIM),
    ("italic", Modifier::ITALIC),
    ("underline", Modifier::UNDERLINED),
    ("reverse", Modifier::REVERSED),
    ("strikethrough", Modifier::CROSSED_OUT),
];

#[derive(Clone, Copy)]
pub(crate) enum Shape {
    Block,
    Bar,
    Underline,
}

#[derive(Clone, Copy)]
pub(crate) struct Cursor {
    pub(crate) row: u16,
    pub(crate) col: u16,
    pub(crate) shape: Shape,
}

pub(crate) trait Surface {
    fn buffer(&mut self) -> &mut Buffer;
    fn size(&mut self) -> io::Result<(u16, u16)>;
    fn present(&mut self, cursor: Option<Cursor>) -> io::Result<()>;
    fn write(&mut self, bytes: &[u8]) -> io::Result<()>;
    fn suspend(&mut self) -> io::Result<()>;
    fn resume(&mut self) -> io::Result<()>;
    fn close(&mut self) -> io::Result<()>;
}

pub(crate) fn row_text(buffer: &Buffer, row: u16) -> String {
    let area = buffer.area;
    (area.left()..area.right())
        .map(|col| buffer[(col, row)].symbol())
        .collect()
}

struct Target {
    area: Rect,
    on_click: Option<Function>,
}

pub(crate) struct Screen {
    surface: Box<dyn Surface>,
    styles: Vec<Style>,
    cursor: Option<Cursor>,
    targets: Vec<Target>,
    flushed: bool,
}

impl Screen {
    pub(crate) fn new(surface: Box<dyn Surface>) -> Self {
        Self {
            surface,
            styles: Vec::new(),
            cursor: None,
            targets: Vec::new(),
            flushed: false,
        }
    }

    pub(crate) fn forget(mut self) -> Self {
        self.targets.clear();
        self
    }

    fn target(&mut self, area: Rect, on_click: Option<Function>) {
        if self.flushed {
            self.flushed = false;
            self.targets.clear();
        }
        if on_click.is_some() || !self.targets.is_empty() {
            self.targets.push(Target { area, on_click });
        }
    }

    fn resolve(&self, id: Option<usize>) -> io::Result<Style> {
        match id {
            None | Some(0) => Ok(Style::default()),
            Some(id) => self
                .styles
                .get(id.saturating_sub(1))
                .copied()
                .ok_or_else(|| io::Error::other(format!("unknown style {id}"))),
        }
    }

    fn put(&mut self, at: (u16, u16), right: u16, text: &str, style: Style) -> u16 {
        let (col, row) = at;
        if col >= right {
            return col;
        }
        let limit = usize::from(right.saturating_sub(col));
        self.surface
            .buffer()
            .set_stringn(col, row, text, limit, style)
            .0
    }

    fn span(&mut self, at: (u16, u16), right: u16, span: Value) -> mlua::Result<u16> {
        let (text, style) = match span {
            Value::String(text) => (text, Style::default()),
            Value::Table(span) => (
                span.raw_get::<mlua::LuaString>(1)?,
                self.resolve(span.raw_get(2)?)?,
            ),
            other => {
                return Err(io::Error::other(format!(
                    "a span is a string or a table, not a {}",
                    other.type_name()
                ))
                .into());
            }
        };
        Ok(self.put(at, right, &String::from_utf8_lossy(&text.as_bytes()), style))
    }

    fn cover(&mut self, area: Rect, style: Style, symbol: &str) {
        let area = area.intersection(self.surface.buffer().area);
        self.target(area, None);
        let buffer = self.surface.buffer();
        for row in area.top()..area.bottom() {
            for col in area.left()..area.right() {
                if let Some(cell) = buffer.cell_mut((col, row)) {
                    cell.reset();
                    cell.set_symbol(symbol);
                    cell.set_style(style);
                }
            }
        }
    }
}

fn region(row: i64, col: i64, width: i64, height: i64) -> Rect {
    let fit = |value: i64| u16::try_from(value.clamp(0, i64::from(u16::MAX))).unwrap_or(u16::MAX);
    let (top, left) = (fit(row), fit(col));
    let (bottom, right) = (
        fit(row.saturating_add(height)),
        fit(col.saturating_add(width)),
    );
    Rect::new(
        left,
        top,
        right.saturating_sub(left),
        bottom.saturating_sub(top),
    )
}

fn color(text: Option<&str>) -> io::Result<Option<Color>> {
    text.map(|text| {
        text.parse::<Color>()
            .map_err(|_| io::Error::other(format!("invalid colour {text}")))
    })
    .transpose()
}

#[options]
struct StyleSpec {
    fg: Option<String>,
    bg: Option<String>,
    #[serde(flatten)]
    flags: HashMap<String, bool>,
}

impl StyleSpec {
    fn style(&self) -> io::Result<Style> {
        let mut style = Style::default();
        if let Some(fg) = color(self.fg.as_deref())? {
            style = style.fg(fg);
        }
        if let Some(bg) = color(self.bg.as_deref())? {
            style = style.bg(bg);
        }
        Ok(MODIFIERS
            .into_iter()
            .filter(|(name, _)| self.flags.get(*name) == Some(&true))
            .fold(style, |style, (_, modifier)| style.add_modifier(modifier)))
    }
}

fn shape(name: Option<&str>) -> io::Result<Shape> {
    match name {
        None | Some("block") => Ok(Shape::Block),
        Some("bar") => Ok(Shape::Bar),
        Some("underline") => Ok(Shape::Underline),
        Some(other) => Err(io::Error::other(format!("unknown cursor shape {other}"))),
    }
}

#[methods(raise)]
impl Screen {
    fn size(&mut self) -> io::Result<(u16, u16)> {
        self.surface.size()
    }

    fn style(&mut self, spec: &StyleSpec) -> io::Result<usize> {
        self.styles.push(spec.style()?);
        Ok(self.styles.len())
    }

    fn line(
        &mut self,
        row: i64,
        col: i64,
        spans: Value,
        width: Option<i64>,
        on_click: Option<Function>,
    ) -> mlua::Result<i64> {
        let area = self.surface.buffer().area;
        let (Ok(top), Ok(left)) = (u16::try_from(row), u16::try_from(col)) else {
            return Ok(col);
        };
        if top >= area.height {
            return Ok(col);
        }
        let right = width.map_or(area.width, |width| {
            region(row, col, width, 1).right().min(area.width)
        });
        self.target(
            Rect::new(left, top, right.saturating_sub(left), 1),
            on_click,
        );
        let end = match spans {
            Value::Nil => Ok(left),
            Value::String(_) => self.span((left, top), right, spans),
            Value::Table(spans) => spans
                .sequence_values::<Value>()
                .try_fold(left, |at, span| self.span((at, top), right, span?)),
            other => Err(io::Error::other(format!(
                "a line is a string or a list of spans, not a {}",
                other.type_name()
            ))
            .into()),
        };
        end.map(i64::from)
    }

    fn fill(
        &mut self,
        row: i64,
        col: i64,
        width: i64,
        height: i64,
        style: Option<usize>,
        symbol: Option<&str>,
    ) -> io::Result<()> {
        let style = self.resolve(style)?;
        self.cover(
            region(row, col, width, height),
            style,
            symbol.unwrap_or(" "),
        );
        Ok(())
    }

    fn paint(
        &mut self,
        row: i64,
        col: i64,
        width: i64,
        height: i64,
        style: usize,
    ) -> io::Result<()> {
        let style = self.resolve(Some(style))?;
        let buffer = self.surface.buffer();
        let area = region(row, col, width, height).intersection(buffer.area);
        buffer.set_style(area, style);
        Ok(())
    }

    fn text(&mut self, row: i64) -> Option<String> {
        let buffer = self.surface.buffer();
        u16::try_from(row)
            .ok()
            .filter(|row| *row < buffer.area.height)
            .map(|row| row_text(buffer, row))
    }

    fn clear(&mut self) {
        self.surface.buffer().reset();
        self.targets.clear();
        self.flushed = false;
    }

    fn clicked(&mut self, row: i64, col: i64) -> Option<Function> {
        let at = Position::new(u16::try_from(col).ok()?, u16::try_from(row).ok()?);
        self.targets
            .iter()
            .rev()
            .find(|target| target.area.contains(at))?
            .on_click
            .clone()
    }

    fn cursor(&mut self, row: Option<i64>, col: Option<i64>, name: Option<&str>) -> io::Result<()> {
        let at = row
            .and_then(|row| u16::try_from(row).ok())
            .zip(col.and_then(|col| u16::try_from(col).ok()));
        self.cursor = match at {
            Some((row, col)) => Some(Cursor {
                row,
                col,
                shape: shape(name)?,
            }),
            None => None,
        };
        Ok(())
    }

    fn flush(&mut self) -> io::Result<()> {
        self.flushed = true;
        self.surface.present(self.cursor)
    }

    fn write(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.surface.write(bytes)
    }

    fn suspend(&mut self) -> io::Result<()> {
        self.surface.suspend()
    }

    fn resume(&mut self) -> io::Result<()> {
        self.surface.resume()
    }

    fn close(&mut self) -> io::Result<()> {
        self.surface.close()
    }
}
