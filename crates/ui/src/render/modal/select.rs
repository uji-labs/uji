use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Clear, Paragraph};

use crate::app::Line as Typed;
use crate::render::Context;
use crate::render::Render;
use crate::render::Surface;

pub(crate) const MAX_ROWS: usize = 12;

pub(crate) struct Select<'a> {
    pub(crate) title: &'a str,
    pub(crate) items: &'a [String],
    pub(crate) query: &'a Typed,
    pub(crate) cursor: usize,
    pub(crate) matches: &'a [usize],
}

impl Render for Select<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let area = surface.area();
        if self.items.is_empty() || area.height < 4 {
            return;
        }
        let current = ctx
            .state
            .current_model()
            .or_else(|| ctx.state.current_provider())
            .unwrap_or_default();

        let matches: Vec<&String> = self
            .matches
            .iter()
            .filter_map(|at| self.items.get(*at))
            .collect();
        let visible = matches
            .len()
            .min(MAX_ROWS)
            .min(usize::from(area.height).saturating_sub(4));
        let start = visible_start(self.cursor, matches.len(), visible);
        let width = usize::from(area.width);

        let mut lines: Vec<Line<'static>> = Vec::new();
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            format!("  {}", self.title),
            Style::default()
                .fg(ctx.palette.text)
                .add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from(""));

        let mut typed = vec![Span::styled("  > ", ctx.palette.accent_style())];
        typed.extend(super::typed(
            self.query,
            false,
            Style::default().fg(ctx.palette.text),
            Style::default().fg(ctx.palette.muted),
        ));
        lines.push(Line::from(typed));
        for (offset, item) in matches[start..start + visible].iter().enumerate() {
            let index = start + offset;
            let active = index == self.cursor;
            let marker = if active { "\u{203a} " } else { "  " };
            let style = if active {
                ctx.palette.accent_style()
            } else {
                Style::default().fg(ctx.palette.text)
            };
            let label = format!("{marker}{item}");
            let label: String = label.chars().take(width).collect();
            let mut spans = vec![Span::styled(label, style)];
            if item.as_str() == current {
                spans.push(Span::styled(
                    " (current)",
                    Style::default().fg(ctx.palette.muted),
                ));
            }
            lines.push(Line::from(spans));
        }

        if matches.len() > visible {
            lines.push(Line::from(Span::styled(
                format!(
                    "  {}\u{2013}{} of {}",
                    start + 1,
                    start + visible,
                    matches.len()
                ),
                Style::default()
                    .fg(ctx.palette.muted)
                    .add_modifier(Modifier::DIM),
            )));
        }

        let height = u16::try_from(lines.len())
            .unwrap_or(u16::MAX)
            .min(area.height);
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

fn visible_start(cursor: usize, len: usize, available: usize) -> usize {
    if len <= available {
        return 0;
    }
    let half = available / 2;
    cursor
        .saturating_sub(half)
        .min(len.saturating_sub(available))
}
