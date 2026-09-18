use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Clear, Paragraph};

use crate::app::{Echo, Line as Typed};
use crate::render::Context;
use crate::render::Render;
use crate::render::Surface;

pub(crate) struct Prompt<'a> {
    pub(crate) title: &'a str,
    pub(crate) value: &'a Typed,
    pub(crate) echo: Echo,
}

pub(crate) const ROWS: u16 = 4;

impl Render for Prompt<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let area = surface.area();
        if area.height == 0 {
            return;
        }
        let mut typed = vec![Span::styled("  > ", ctx.palette.accent_style())];
        typed.extend(super::typed(
            self.value,
            self.echo,
            Style::default().fg(ctx.palette.text),
            Style::default().fg(ctx.palette.muted),
        ));

        let lines = vec![
            Line::from(""),
            Line::from(Span::styled(
                format!("  {}", self.title),
                Style::default()
                    .fg(ctx.palette.text)
                    .add_modifier(Modifier::BOLD),
            )),
            Line::from(""),
            Line::from(typed),
        ];

        let height = ROWS.min(area.height);
        let popup = Rect {
            x: area.x,
            y: area.y + area.height.saturating_sub(height),
            width: area.width,
            height,
        };
        surface.render_at(popup, Clear);
        surface.render_at(popup, Paragraph::new(lines));
    }
}
