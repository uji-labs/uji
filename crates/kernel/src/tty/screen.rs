use mlua::{Table, UserData, UserDataMethods, Value};
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};

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
    fn size(&mut self) -> mlua::Result<(u16, u16)>;
    fn present(&mut self, cursor: Option<Cursor>) -> mlua::Result<()>;
    fn write(&mut self, bytes: &[u8]) -> mlua::Result<()>;
    fn suspend(&mut self) -> mlua::Result<()>;
    fn resume(&mut self) -> mlua::Result<()>;
    fn close(&mut self) -> mlua::Result<()>;
}

pub(crate) struct Screen {
    surface: Box<dyn Surface>,
    styles: Vec<Style>,
    cursor: Option<Cursor>,
}

impl Screen {
    pub(crate) fn new(surface: Box<dyn Surface>) -> Self {
        Self {
            surface,
            styles: Vec::new(),
            cursor: None,
        }
    }

    fn style(&self, id: Option<usize>) -> mlua::Result<Style> {
        match id {
            None | Some(0) => Ok(Style::default()),
            Some(id) => self
                .styles
                .get(id.saturating_sub(1))
                .copied()
                .ok_or_else(|| mlua::Error::runtime(format!("unknown style {id}"))),
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

    fn line(&mut self, row: u16, col: u16, spans: Value, width: Option<u16>) -> mlua::Result<u16> {
        let area = self.surface.buffer().area;
        if row >= area.height {
            return Ok(col);
        }
        let right = width.map_or(area.width, |width| {
            col.saturating_add(width).min(area.width)
        });
        let mut at = col;
        match spans {
            Value::String(text) => {
                at = self.put((at, row), right, &text.to_string_lossy(), Style::default());
            }
            Value::Table(spans) => {
                for span in spans.sequence_values::<Value>() {
                    let (text, style) = match span? {
                        Value::String(text) => (text, Style::default()),
                        Value::Table(span) => {
                            let style = self.style(span.raw_get::<Option<usize>>(2)?)?;
                            (span.raw_get::<mlua::LuaString>(1)?, style)
                        }
                        other => {
                            return Err(mlua::Error::runtime(format!(
                                "a span is a string or a table, not a {}",
                                other.type_name()
                            )));
                        }
                    };
                    at = self.put((at, row), right, &text.to_string_lossy(), style);
                }
            }
            Value::Nil => {}
            other => {
                return Err(mlua::Error::runtime(format!(
                    "a line is a string or a list of spans, not a {}",
                    other.type_name()
                )));
            }
        }
        Ok(at)
    }

    fn text(&mut self, row: u16) -> Option<String> {
        let buffer = self.surface.buffer();
        let area = buffer.area;
        (row < area.height).then(|| {
            (area.left()..area.right())
                .map(|col| buffer[(col, row)].symbol())
                .collect()
        })
    }

    fn fill(&mut self, area: Rect, style: Style, symbol: &str) {
        let buffer = self.surface.buffer();
        let area = area.intersection(buffer.area);
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

fn color(text: &str) -> mlua::Result<Color> {
    text.parse::<Color>()
        .map_err(|_| mlua::Error::runtime(format!("invalid colour {text}")))
}

fn parse_style(spec: &Table) -> mlua::Result<Style> {
    let mut style = Style::default();
    if let Some(fg) = spec.get::<Option<String>>("fg")? {
        style = style.fg(color(&fg)?);
    }
    if let Some(bg) = spec.get::<Option<String>>("bg")? {
        style = style.bg(color(&bg)?);
    }
    for (key, modifier) in MODIFIERS {
        if spec.get::<Option<bool>>(key)?.unwrap_or(false) {
            style = style.add_modifier(modifier);
        }
    }
    Ok(style)
}

fn shape(name: Option<&str>) -> mlua::Result<Shape> {
    match name {
        None | Some("block") => Ok(Shape::Block),
        Some("bar") => Ok(Shape::Bar),
        Some("underline") => Ok(Shape::Underline),
        Some(other) => Err(mlua::Error::runtime(format!(
            "unknown cursor shape {other}"
        ))),
    }
}

impl UserData for Screen {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method_mut("size", |_, screen, ()| screen.surface.size());
        methods.add_method_mut("style", |_, screen, spec: Table| {
            screen.styles.push(parse_style(&spec)?);
            Ok(screen.styles.len())
        });
        methods.add_method_mut(
            "line",
            |_, screen, (row, col, spans, width): (u16, u16, Value, Option<u16>)| {
                screen.line(row, col, spans, width)
            },
        );
        methods.add_method_mut(
            "fill",
            |_,
             screen,
             (row, col, width, height, style, symbol): (
                u16,
                u16,
                u16,
                u16,
                Option<usize>,
                Option<String>,
            )| {
                let style = screen.style(style)?;
                screen.fill(
                    Rect::new(col, row, width, height),
                    style,
                    symbol.as_deref().unwrap_or(" "),
                );
                Ok(())
            },
        );
        methods.add_method_mut(
            "paint",
            |_, screen, (row, col, width, height, style): (u16, u16, u16, u16, usize)| {
                let style = screen.style(Some(style))?;
                let buffer = screen.surface.buffer();
                let area = Rect::new(col, row, width, height).intersection(buffer.area);
                buffer.set_style(area, style);
                Ok(())
            },
        );
        methods.add_method_mut("text", |_, screen, row: u16| Ok(screen.text(row)));
        methods.add_method_mut("clear", |_, screen, ()| {
            screen.surface.buffer().reset();
            Ok(())
        });
        methods.add_method_mut(
            "cursor",
            |_, screen, (row, col, name): (Option<u16>, Option<u16>, Option<String>)| {
                screen.cursor = match (row, col) {
                    (Some(row), Some(col)) => Some(Cursor {
                        row,
                        col,
                        shape: shape(name.as_deref())?,
                    }),
                    _ => None,
                };
                Ok(())
            },
        );
        methods.add_method_mut("flush", |_, screen, ()| {
            let cursor = screen.cursor;
            screen.surface.present(cursor)
        });
        methods.add_method_mut("write", |_, screen, bytes: mlua::LuaString| {
            screen.surface.write(&bytes.as_bytes())
        });
        methods.add_method_mut("suspend", |_, screen, ()| screen.surface.suspend());
        methods.add_method_mut("resume", |_, screen, ()| screen.surface.resume());
        methods.add_method_mut("close", |_, screen, ()| screen.surface.close());
    }
}
