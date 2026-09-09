use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use uji_api::model::WindowSpec;

use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{TEXT, block_for, color_of};

pub(crate) struct Input<'a> {
    pub(crate) window: &'a WindowSpec,
}

impl Render for Input<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
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
        let paragraph = match block_for(self.window) {
            Some(block) => paragraph.block(block),
            None => paragraph,
        };
        surface.render_widget(paragraph);
    }
}
