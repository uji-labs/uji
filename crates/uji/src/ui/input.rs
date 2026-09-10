use ratatui::layout::{Alignment, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use uji_api::model::{ConfirmOpts, WindowSpec};

use crate::app::Mode;
use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, TEXT, accent_style, block_for, color_of};

pub(crate) struct Input<'a> {
    pub(crate) window: &'a WindowSpec,
}

impl Render for Input<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        match ctx.app.mode() {
            Mode::Confirm { title, body, allow } => {
                render_confirm(surface, title, body, *allow, &ctx.state.opts().confirm);
            }
            _ => self.render_input(ctx, surface),
        }
    }
}

impl Input<'_> {
    fn render_input(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let block = block_for(self.window);
        let cursor_offset = ctx.app.cursor_offset();
        let before = &ctx.app.input()[..cursor_offset];
        let after = ctx.app.input()[cursor_offset..].to_owned();

        let text_style = match ctx.state.opts().input_color {
            Some(color) => Style::default().fg(color_of(color)),
            None => Style::default().fg(TEXT),
        };
        let mut cursor_style = Style::default().fg(Color::White);
        if ctx.state.opts().cursor_blink {
            cursor_style = cursor_style.add_modifier(Modifier::SLOW_BLINK);
        }
        let cursor = Span::styled("█", cursor_style);
        let line = Line::from(vec![
            Span::styled(before.to_owned(), text_style),
            cursor,
            Span::styled(after, text_style),
        ]);

        let paragraph = Paragraph::new(line);
        let paragraph = match block {
            Some(block) => paragraph.block(block),
            None => paragraph,
        };
        surface.render_widget(paragraph);
    }
}

fn render_confirm(
    surface: &mut Surface<'_>,
    title: &str,
    body: &str,
    allow: bool,
    confirm: &ConfirmOpts,
) {
    let area = surface.area();
    let width = usize::from(area.width);

    let selected = match confirm.selected {
        Some(color) => Style::default().fg(color_of(color)),
        None => accent_style(),
    };
    let unselected = match confirm.unselected {
        Some(color) => Style::default().fg(color_of(color)),
        None => Style::default().fg(MUTED),
    };
    let title_style = match confirm.title_color {
        Some(color) => Style::default().bold().fg(color_of(color)),
        None => Style::default().bold().fg(TEXT),
    };
    let body_style = match confirm.body_color {
        Some(color) => Style::default().fg(color_of(color)),
        None => Style::default().fg(MUTED),
    };

    let body: String = body.chars().take(width).collect();
    let yes_text = format!("[ {} ]", confirm.yes);
    let no_text = format!("[ {} ]", confirm.no);
    let buttons = Line::from(vec![
        Span::styled(yes_text, if allow { selected } else { unselected }),
        Span::raw("  "),
        Span::styled(no_text, if allow { unselected } else { selected }),
    ]);

    surface.render_at(
        Rect {
            x: area.x,
            y: area.y,
            width: area.width,
            height: 1,
        },
        Paragraph::new(Line::styled(title.to_string(), title_style)),
    );
    surface.render_at(
        Rect {
            x: area.x,
            y: area.y + 1,
            width: area.width,
            height: 1,
        },
        Paragraph::new(Line::styled(body, body_style)),
    );
    surface.render_at(
        Rect {
            x: area.x,
            y: area.y + 2,
            width: area.width,
            height: 1,
        },
        Paragraph::new(buttons).alignment(Alignment::Center),
    );
}
