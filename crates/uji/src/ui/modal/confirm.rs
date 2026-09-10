use ratatui::layout::{Alignment, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;

use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, TEXT, accent_style};

use super::menu::draw_border;

pub(crate) struct Confirm<'a> {
    pub(crate) title: &'a str,
    pub(crate) body: &'a str,
    pub(crate) allow: bool,
}

impl Render for Confirm<'_> {
    fn render(&self, _ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let area = surface.area();
        let width = area.width.clamp(40, 72);
        let height = 6;
        let x = area.x + area.width.saturating_sub(width) / 2;
        let y = area.y + area.height.saturating_sub(height) / 2;
        let popup = Rect {
            x,
            y,
            width,
            height,
        };

        draw_border(surface.buf(), popup);

        let inner = Rect {
            x: popup.x + 1,
            y: popup.y + 1,
            width: popup.width.saturating_sub(2),
            height: popup.height.saturating_sub(2),
        };

        surface.render_at(
            Rect {
                x: inner.x,
                y: inner.y,
                width: inner.width,
                height: 1,
            },
            Paragraph::new(Line::styled(
                self.title.to_string(),
                Style::default().bold(),
            ))
            .alignment(Alignment::Center),
        );

        surface.render_at(
            Rect {
                x: inner.x,
                y: inner.y + 1,
                width: inner.width,
                height: 2,
            },
            Paragraph::new(Line::styled(
                self.body.to_string(),
                Style::default().fg(TEXT),
            )),
        );

        let allow_style = if self.allow {
            accent_style()
        } else {
            Style::default().fg(MUTED)
        };
        let deny_style = if self.allow {
            Style::default().fg(MUTED)
        } else {
            accent_style()
        };
        let buttons = Line::from(vec![
            Span::styled("[ Allow ]", allow_style),
            Span::raw("  "),
            Span::styled("[ Deny ]", deny_style),
        ]);
        surface.render_at(
            Rect {
                x: inner.x,
                y: inner.y + inner.height.saturating_sub(1),
                width: inner.width,
                height: 1,
            },
            Paragraph::new(buttons).alignment(Alignment::Center),
        );
    }
}
