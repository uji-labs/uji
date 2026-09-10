use ratatui::layout::Rect;
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use uji_api::model::WindowSpec;

use crate::app::Mode;
use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, TEXT, block_for, color_of};
use crate::ui::wrap;

const CURSOR: char = '█';

pub(crate) struct Input<'a> {
    pub(crate) window: &'a WindowSpec,
}

impl Render for Input<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        match ctx.app.mode() {
            Mode::Confirm { .. } => render_confirm_hint(surface),
            _ => self.render_input(ctx, surface),
        }
    }
}

impl Input<'_> {
    fn render_input(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let block = block_for(self.window);
        let inner = block
            .as_ref()
            .map_or(surface.area(), |block| block.inner(surface.area()));
        let height = usize::from(inner.height).max(1);

        let text_style = ctx.state.opts().input_color.map_or_else(
            || Style::default().fg(TEXT),
            |color| Style::default().fg(color_of(color)),
        );
        let mut cursor_style = Style::default().fg(Color::White);
        if ctx.state.opts().cursor_blink {
            cursor_style = cursor_style.add_modifier(Modifier::SLOW_BLINK);
        }

        let input = ctx.app.input();
        let cursor = input[..ctx.app.cursor_offset()].chars().count();
        let display = with_cursor(input, cursor);
        let rows = wrap::ranges(&display, usize::from(inner.width));
        let cursor_row = rows
            .iter()
            .position(|(start, end)| (*start..*end).contains(&cursor))
            .unwrap_or(0);

        let lines: Vec<Line<'static>> = rows
            .iter()
            .skip(cursor_row.saturating_sub(height - 1))
            .take(height)
            .map(|&(start, end)| {
                let row = &display[start..end];
                if !(start..end).contains(&cursor) {
                    return Line::from(Span::styled(collect(row), text_style));
                }
                let split = cursor - start;
                Line::from(vec![
                    Span::styled(collect(&row[..split]), text_style),
                    Span::styled(String::from(CURSOR), cursor_style),
                    Span::styled(collect(&row[split + 1..]), text_style),
                ])
            })
            .collect();

        let paragraph = Paragraph::new(lines);
        let paragraph = match block {
            Some(block) => paragraph.block(block),
            None => paragraph,
        };
        surface.render_widget(paragraph);
    }
}

pub(crate) fn rows_needed(input: &str, width: usize) -> usize {
    let display = with_cursor(input, input.chars().count());
    wrap::ranges(&display, width).len()
}

fn with_cursor(input: &str, at: usize) -> Vec<char> {
    let mut display: Vec<char> = input.chars().collect();
    display.insert(at.min(display.len()), CURSOR);
    display
}

fn collect(chars: &[char]) -> String {
    chars.iter().collect()
}

fn render_confirm_hint(surface: &mut Surface<'_>) {
    let area = surface.area();
    if area.height == 0 {
        return;
    }
    let hint = Line::from(Span::styled(
        "  Press enter to confirm or esc to cancel",
        Style::default().fg(MUTED).add_modifier(Modifier::DIM),
    ));
    surface.render_at(
        Rect {
            x: area.x,
            y: area.y,
            width: area.width,
            height: 1,
        },
        Paragraph::new(hint),
    );
}
