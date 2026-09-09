use ratatui::style::{Color, Modifier, Style};
use ratatui::text::Line;
use ratatui::widgets::Paragraph;
use uji_api::model::WindowSpec;

use crate::session::model::Message;
use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, TEXT, USER_BG, block_for};

pub(crate) struct Messages<'a> {
    pub(crate) window: &'a WindowSpec,
}

impl Render for Messages<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let block = block_for(self.window);
        let inner = block
            .as_ref()
            .map_or(surface.area(), |b| b.inner(surface.area()));
        let fill = " ".repeat(usize::from(inner.width));
        let mut lines = Vec::new();
        for stored in ctx.app.messages() {
            match &stored.message {
                Message::User { text } => {
                    let block_style = Style::default().bg(USER_BG).fg(TEXT);
                    lines.push(Line::from(fill.clone()).style(block_style));
                    for line in text.lines() {
                        lines.push(Line::from(format!(" {line} {fill}")).style(block_style));
                    }
                    lines.push(Line::from(fill.clone()).style(block_style));
                }
                Message::Assistant { text } => {
                    lines.push(Line::from(""));
                    let text_style = Style::default().fg(TEXT);
                    for line in text.lines() {
                        lines.push(Line::from(format!(" {line}")).style(text_style));
                    }
                }
                Message::System { text } => {
                    lines.push(Line::from(""));
                    let muted = Style::default().fg(MUTED).add_modifier(Modifier::ITALIC);
                    for line in text.lines() {
                        lines.push(Line::from(format!(" {line}")).style(muted));
                    }
                }
                Message::Error { text } => {
                    lines.push(Line::from(""));
                    let error = Style::default().fg(Color::Red);
                    for line in text.lines() {
                        lines.push(Line::from(format!(" {line}")).style(error));
                    }
                }
            }
        }
        if let Some(pending) = ctx.app.pending().filter(|text| !text.is_empty()) {
            lines.push(Line::from(""));
            let text_style = Style::default().fg(TEXT);
            for line in pending.lines() {
                lines.push(Line::from(format!(" {line}")).style(text_style));
            }
        }
        let paragraph = Paragraph::new(lines);
        let paragraph = match block {
            Some(block) => paragraph.block(block),
            None => paragraph,
        };
        surface.render_widget(paragraph);
    }
}
