use crate::model::WindowSpec;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;

use crate::app::Mode;
use crate::model::Builtin;
use crate::render::Context;
use crate::render::Render;
use crate::render::Surface;
use crate::render::modal::confirm;
use crate::render::style::{block_for, color_of};
use crate::render::wrap;

const CURSOR: char = '█';

#[derive(Default)]
pub struct Layout {
    key: (u64, usize, usize, bool),
    ready: bool,
    display: Vec<char>,
    cursor: usize,
    rows: Vec<(usize, usize)>,
}

impl Layout {
    fn sync(&mut self, app: &crate::app::App, width: usize) {
        let focused = app.focus() == Builtin::Input;
        let key = (app.input_revision(), app.cursor_offset(), width, focused);
        if self.ready && self.key == key {
            return;
        }
        self.key = key;
        self.ready = true;
        let input = app.input();
        self.cursor = input[..app.cursor_offset()].chars().count();
        self.display.clear();
        self.display.extend(input.chars());
        if focused {
            self.display
                .insert(self.cursor.min(self.display.len()), CURSOR);
        }
        self.rows.clear();
        self.rows.extend(wrap::ranges(&self.display, width));
    }
}

pub(crate) struct Input<'a> {
    pub(crate) window: &'a WindowSpec,
}

impl Render for Input<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        match ctx.app.mode() {
            Mode::Confirm { title, body, allow } => {
                let block = block_for(self.window, ctx.palette);
                let inner = block
                    .as_ref()
                    .map_or(surface.area(), |block| block.inner(surface.area()));
                let lines = confirm::lines(ctx, title, body, confirm::choice(*allow), inner.width);
                let paragraph = Paragraph::new(lines);
                match block {
                    Some(block) => surface.render_widget(paragraph.block(block)),
                    None => surface.render_widget(paragraph),
                }
            }
            _ => self.render_input(ctx, surface),
        }
    }
}

impl Input<'_> {
    fn render_input(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let block = block_for(self.window, ctx.palette);
        let inner = block
            .as_ref()
            .map_or(surface.area(), |block| block.inner(surface.area()));
        let height = usize::from(inner.height).max(1);

        let text_style = ctx.state.opts().input_color.map_or_else(
            || Style::default().fg(ctx.palette.text),
            |color| Style::default().fg(color_of(color)),
        );
        let mut cursor_style = Style::default().fg(ctx.palette.cursor);
        if ctx.state.opts().cursor_blink {
            cursor_style = cursor_style.add_modifier(Modifier::SLOW_BLINK);
        }

        let mut typed = ctx.app.typed();
        typed.sync(ctx.app, usize::from(inner.width));
        let Layout {
            display,
            cursor,
            rows,
            ..
        } = &*typed;
        let cursor = *cursor;
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

        if let Some(block) = block {
            surface.render_widget(block);
        }
        crate::render::write_lines(surface, inner, lines.iter());
    }
}

pub(crate) fn rows_needed(app: &crate::app::App, width: usize) -> usize {
    let mut typed = app.typed();
    typed.sync(app, width);
    typed.rows.len()
}

/// Newlines are row breaks, not glyphs: the row they end already exists, so
/// drawing them would only push the rest of the row off by a cell.
fn collect(chars: &[char]) -> String {
    chars.iter().filter(|c| **c != '\n').collect()
}
