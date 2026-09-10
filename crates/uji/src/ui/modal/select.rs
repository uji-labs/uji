use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Clear, Paragraph};

use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, TEXT, accent_style};

const MAX_ROWS: usize = 12;

pub(crate) struct Select<'a> {
    pub(crate) title: &'a str,
    pub(crate) items: &'a [String],
    pub(crate) cursor: usize,
}

impl Render for Select<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let area = surface.area();
        if self.items.is_empty() || area.height < 3 {
            return;
        }
        let current = ctx
            .state
            .current_model()
            .or_else(|| ctx.state.current_provider())
            .unwrap_or_default();

        let visible = self
            .items
            .len()
            .min(MAX_ROWS)
            .min(usize::from(area.height).saturating_sub(3));
        let start = visible_start(self.cursor, self.items.len(), visible);
        let width = usize::from(area.width);

        let mut lines: Vec<Line<'static>> = Vec::new();
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            format!("  {}", self.title),
            Style::default().fg(TEXT).add_modifier(Modifier::BOLD),
        )));
        lines.push(Line::from(""));

        for (offset, item) in self.items[start..start + visible].iter().enumerate() {
            let index = start + offset;
            let active = index == self.cursor;
            let marker = if active { "\u{203a} " } else { "  " };
            let style = if active {
                accent_style()
            } else {
                Style::default().fg(TEXT)
            };
            let label = format!("{marker}{}. {item}", index + 1);
            let label: String = label.chars().take(width).collect();
            let mut spans = vec![Span::styled(label, style)];
            if item == current {
                spans.push(Span::styled(" (current)", Style::default().fg(MUTED)));
            }
            lines.push(Line::from(spans));
        }

        if self.items.len() > visible {
            lines.push(Line::from(Span::styled(
                format!(
                    "  {}\u{2013}{} of {}",
                    start + 1,
                    start + visible,
                    self.items.len()
                ),
                Style::default().fg(MUTED).add_modifier(Modifier::DIM),
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
