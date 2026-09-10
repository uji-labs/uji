use ratatui::layout::{Alignment, Constraint, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;

use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, accent_style, border_fade};

pub(crate) struct Menu<'a> {
    pub(crate) area: Rect,
    pub(crate) title: &'a str,
    pub(crate) rows: Vec<Line<'static>>,
}

impl Render for Menu<'_> {
    fn render(&self, _ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let [body, footer] =
            Layout::vertical([Constraint::Fill(1), Constraint::Length(1)]).areas(self.area);

        draw_border(surface.buf(), body);

        let inner = Rect {
            x: body.x + 1,
            y: body.y + 1,
            width: body.width.saturating_sub(2),
            height: body.height.saturating_sub(2),
        };

        let title_area = Rect {
            x: inner.x,
            y: inner.y,
            width: inner.width,
            height: 1,
        };
        surface.render_at(
            title_area,
            Paragraph::new(Line::styled(
                self.title.to_string(),
                Style::default().bold(),
            ))
            .alignment(Alignment::Center),
        );

        let rows_area = Rect {
            x: inner.x,
            y: inner.y + 1,
            width: inner.width,
            height: inner.height.saturating_sub(1),
        };
        surface.render_at(rows_area, Paragraph::new(self.rows.clone()));

        let muted = Style::default().fg(MUTED);
        let hint = Line::from(vec![
            Span::styled("⏎", accent_style()),
            Span::styled(" confirm   ", muted),
            Span::styled("esc", accent_style()),
            Span::styled(" cancel", muted),
        ]);
        surface.render_at(footer, Paragraph::new(hint));
    }
}

fn draw_border(buf: &mut ratatui::buffer::Buffer, area: Rect) {
    let w = area.width;
    let h = area.height;
    if w < 3 || h < 3 {
        return;
    }
    for i in 1..w - 1 {
        let x = area.x + i;
        let d = i.min(w - 1 - i);
        let style = border_fade(d);
        buf[(x, area.y)].set_symbol("─");
        buf[(x, area.y)].set_style(style);
        buf[(x, area.y + h - 1)].set_symbol("─");
        buf[(x, area.y + h - 1)].set_style(style);
    }
    for j in 1..h - 1 {
        let y = area.y + j;
        let d = j.min(h - 1 - j);
        let style = border_fade(d);
        buf[(area.x, y)].set_symbol("│");
        buf[(area.x, y)].set_style(style);
        buf[(area.x + w - 1, y)].set_symbol("│");
        buf[(area.x + w - 1, y)].set_style(style);
    }
}
