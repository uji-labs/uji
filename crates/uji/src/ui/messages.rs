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
        let width = usize::from(inner.width);
        let height = usize::from(inner.height);
        let fill = " ".repeat(width);
        let mut lines = Vec::new();
        let mut first = true;

        for stored in ctx.app.messages() {
            if !first {
                lines.push(Line::from(""));
            }
            first = false;
            match &stored.message {
                Message::User { text } => {
                    let style = Style::default().bg(USER_BG).fg(TEXT);
                    lines.push(Line::from(fill.clone()).style(style));
                    push_wrapped(&mut lines, text, width.saturating_sub(2), style, " ", true);
                    lines.push(Line::from(fill.clone()).style(style));
                }
                Message::Assistant { text, .. } => {
                    let style = Style::default().fg(TEXT);
                    push_wrapped(&mut lines, text, width.saturating_sub(1), style, " ", false);
                }
                Message::Tool { name, content, .. } => {
                    lines.push(
                        Line::from(format!(" ⏺ {name}")).style(Style::default().fg(Color::Cyan)),
                    );
                    push_wrapped(
                        &mut lines,
                        content,
                        width.saturating_sub(3),
                        Style::default().fg(MUTED),
                        "   ",
                        false,
                    );
                }
                Message::System { text } => {
                    let style = Style::default().fg(MUTED).add_modifier(Modifier::ITALIC);
                    push_wrapped(&mut lines, text, width.saturating_sub(1), style, " ", false);
                }
                Message::Error { text } => {
                    let style = Style::default().fg(Color::Red);
                    push_wrapped(&mut lines, text, width.saturating_sub(1), style, " ", false);
                }
            }
        }
        if let Some(pending) = ctx.app.pending().filter(|text| !text.is_empty()) {
            if !lines.is_empty() {
                lines.push(Line::from(""));
            }
            push_wrapped(
                &mut lines,
                pending,
                width.saturating_sub(1),
                Style::default().fg(TEXT),
                " ",
                false,
            );
        }

        let total = lines.len();
        let max_scroll = total.saturating_sub(height);
        let current = ctx.app.scroll();
        let follow = current == usize::MAX || current >= ctx.app.last_max();
        let offset = if follow {
            max_scroll
        } else {
            current.min(max_scroll)
        };
        ctx.app.set_scroll(offset);
        ctx.app.set_last_max(max_scroll);
        ctx.app.set_viewport(height);
        let start = offset;
        let end = (start + height).min(total);
        let paragraph = Paragraph::new(lines[start..end].to_vec());
        let paragraph = match block {
            Some(block) => paragraph.block(block),
            None => paragraph,
        };
        surface.render_widget(paragraph);
    }
}

fn push_wrapped(
    lines: &mut Vec<Line<'static>>,
    text: &str,
    width: usize,
    style: Style,
    prefix: &str,
    full: bool,
) {
    for chunk in wrap_text(text, width) {
        if full {
            let pad = " ".repeat(width.saturating_sub(chunk.chars().count()));
            lines.push(Line::from(format!("{prefix}{chunk} {pad}")).style(style));
        } else {
            lines.push(Line::from(format!("{prefix}{chunk}")).style(style));
        }
    }
}

fn wrap_text(text: &str, width: usize) -> Vec<String> {
    if width == 0 {
        return text.lines().map(str::to_string).collect();
    }
    let mut out = Vec::new();
    for line in text.lines() {
        if line.chars().count() <= width {
            out.push(line.to_string());
            continue;
        }
        let mut current = String::new();
        for word in line.split_whitespace() {
            let word_len = word.chars().count();
            if word_len > width {
                if !current.is_empty() {
                    out.push(std::mem::take(&mut current));
                }
                for ch in word.chars() {
                    if current.chars().count() == width {
                        out.push(std::mem::take(&mut current));
                    }
                    current.push(ch);
                }
                continue;
            }
            if current.chars().count() + 1 + word_len > width {
                out.push(std::mem::take(&mut current));
            } else if !current.is_empty() {
                current.push(' ');
            }
            current.push_str(word);
        }
        if !current.is_empty() {
            out.push(current);
        }
    }
    out
}
