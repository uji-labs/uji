use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Paragraph};

use crate::app::Line as Typed;
use crate::render::{Context, Render, Surface};

/// Results on the left, a preview of the highlighted one on the right, and the
/// query below both.
pub(crate) struct Pick<'a> {
    pub(crate) title: &'a str,
    pub(crate) items: &'a [String],
    pub(crate) query: &'a Typed,
    pub(crate) cursor: usize,
    pub(crate) matches: &'a [usize],
    pub(crate) preview: &'a [String],
}

const PROMPT_ROWS: u16 = 3;
const MIN_PREVIEW: u16 = 24;

impl Render for Pick<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let area = surface.area();
        if area.height < PROMPT_ROWS.saturating_add(3) || area.width < 20 {
            return;
        }
        surface.render_widget(Clear);

        let body = Rect {
            height: area.height.saturating_sub(PROMPT_ROWS),
            ..area
        };
        let split = preview_split(body.width);
        let results = Rect {
            width: split,
            ..body
        };
        let preview = Rect {
            x: body.x.saturating_add(split),
            width: body.width.saturating_sub(split),
            ..body
        };
        let prompt = Rect {
            y: body.y.saturating_add(body.height),
            height: PROMPT_ROWS,
            ..area
        };

        self.results(ctx, surface, results);
        self.preview(ctx, surface, preview);
        self.prompt(ctx, surface, prompt);
    }
}

/// Give the preview half the width once there is room for it to be useful.
fn preview_split(width: u16) -> u16 {
    if width < MIN_PREVIEW.saturating_mul(2) {
        width
    } else {
        width / 2
    }
}

impl Pick<'_> {
    fn results(&self, ctx: &Context<'_>, surface: &mut Surface<'_>, area: Rect) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(ctx.palette.muted))
            .title(Span::styled(
                format!(" {} ", self.title),
                ctx.palette.accent_style(),
            ));
        let inner = block.inner(area);
        let rows = usize::from(inner.height);
        let start = self.cursor.saturating_sub(rows.saturating_sub(1));
        let lines: Vec<Line<'static>> = self
            .matches
            .iter()
            .enumerate()
            .skip(start)
            .take(rows)
            .map(|(at, index)| {
                let text = self.items.get(*index).cloned().unwrap_or_default();
                if at == self.cursor {
                    Line::from(Span::styled(
                        format!("> {text}"),
                        Style::default()
                            .bg(ctx.palette.selected_bg)
                            .fg(ctx.palette.text),
                    ))
                } else {
                    Line::from(Span::styled(
                        format!("  {text}"),
                        Style::default().fg(ctx.palette.text),
                    ))
                }
            })
            .collect();
        surface.render_at(area, Paragraph::new(lines).block(block));
    }

    fn preview(&self, ctx: &Context<'_>, surface: &mut Surface<'_>, area: Rect) {
        if area.width == 0 {
            return;
        }
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(ctx.palette.muted));
        let rows = usize::from(block.inner(area).height);
        let lines: Vec<Line<'static>> = self
            .preview
            .iter()
            .take(rows)
            .map(|line| {
                Line::from(Span::styled(
                    line.clone(),
                    Style::default().fg(ctx.palette.muted),
                ))
            })
            .collect();
        surface.render_at(area, Paragraph::new(lines).block(block));
    }

    fn prompt(&self, ctx: &Context<'_>, surface: &mut Surface<'_>, area: Rect) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(ctx.palette.muted));
        let mut spans = vec![Span::styled("> ", ctx.palette.accent_style())];
        spans.extend(super::typed(
            self.query,
            crate::app::Echo::Plain,
            Style::default().fg(ctx.palette.text),
            Style::default().fg(ctx.palette.muted),
        ));
        spans.push(Span::styled(
            format!("   {}/{}", self.matches.len(), self.items.len()),
            Style::default()
                .fg(ctx.palette.muted)
                .add_modifier(Modifier::DIM),
        ));
        surface.render_at(area, Paragraph::new(Line::from(spans)).block(block));
    }
}
