use ratatui::style::{Color as TColor, Modifier, Style};
use ratatui::symbols;
use ratatui::widgets::{Block, Borders, Padding};
use uji_api::model::{Border, Color, Style as ApiStyle, WindowSpec};

pub(crate) const USER_BG: TColor = TColor::Rgb(0x34, 0x35, 0x41);
pub(crate) const TEXT: TColor = TColor::Rgb(0xd4, 0xd4, 0xd4);
pub(crate) const MUTED: TColor = TColor::Rgb(0x80, 0x80, 0x80);
pub(crate) const SELECTED_BG: TColor = TColor::Rgb(0x3a, 0x3a, 0x4a);

pub(crate) fn accent_style() -> Style {
    Style::default()
        .fg(TColor::Cyan)
        .add_modifier(Modifier::BOLD)
}

pub(crate) fn color_of(color: Color) -> TColor {
    match color {
        Color::Black => TColor::Black,
        Color::Red => TColor::Red,
        Color::Green => TColor::Green,
        Color::Yellow => TColor::Yellow,
        Color::Blue => TColor::Blue,
        Color::Magenta => TColor::Magenta,
        Color::Cyan => TColor::Cyan,
        Color::Gray => TColor::Gray,
        Color::DarkGray => TColor::DarkGray,
        Color::LightRed => TColor::LightRed,
        Color::LightGreen => TColor::LightGreen,
        Color::LightYellow => TColor::LightYellow,
        Color::LightBlue => TColor::LightBlue,
        Color::LightMagenta => TColor::LightMagenta,
        Color::LightCyan => TColor::LightCyan,
        Color::White => TColor::White,
        Color::Rgb(r, g, b) => TColor::Rgb(r, g, b),
    }
}

pub(crate) fn span_style(style: &ApiStyle) -> Style {
    let mut out = Style::default();
    if let Some(fg) = style.fg {
        out = out.fg(color_of(fg));
    }
    if let Some(bg) = style.bg {
        out = out.bg(color_of(bg));
    }
    if style.bold {
        out = out.add_modifier(Modifier::BOLD);
    }
    if style.italic {
        out = out.add_modifier(Modifier::ITALIC);
    }
    if style.underline {
        out = out.add_modifier(Modifier::UNDERLINED);
    }
    out
}

pub(crate) fn span_background(style: &ApiStyle) -> Option<TColor> {
    style.bg.map(color_of)
}

pub(crate) fn border_fade(d: u16) -> Style {
    let v = match d {
        0 => 0x1a,
        1 => 0x2c,
        2 => 0x3e,
        _ => 0x50,
    };
    Style::default().fg(TColor::Rgb(v, v, v + 3))
}

pub(crate) fn block_for(win: &WindowSpec) -> Option<Block<'static>> {
    let borders = match win.opts.border {
        Border::None => Borders::NONE,
        Border::Plain | Border::Rounded => Borders::ALL,
        Border::Horizontal => Borders::TOP | Borders::BOTTOM,
    };
    if win.opts.border == Border::None && win.opts.padding == 0 {
        return None;
    }
    let mut block = match win.opts.border {
        Border::Rounded => Block::default()
            .borders(borders)
            .border_set(symbols::border::ROUNDED),
        _ => Block::default().borders(borders),
    };
    block = block.padding(Padding::vertical(win.opts.padding));
    let border_style = win.opts.border_color.map_or_else(
        || Style::default().fg(MUTED),
        |color| Style::default().fg(color_of(color)),
    );
    block = block.style(border_style);
    if let Some(title) = &win.opts.title {
        block = block.title(title.clone());
    }
    Some(block)
}
