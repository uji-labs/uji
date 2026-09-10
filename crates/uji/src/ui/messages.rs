use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Paragraph;
use uji_api::model::WindowSpec;

use crate::session::model::Message;
use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, TEXT, USER_BG, block_for};
use crate::ui::wrap::text as wrap_text;

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

        let mut in_tool_group = false;
        for stored in ctx.app.messages() {
            let grouped = in_tool_group && matches!(stored.message, Message::Tool { .. });
            if !first && !grouped {
                lines.push(Line::from(""));
            }
            first = false;
            in_tool_group = false;
            match &stored.message {
                Message::User { text } => {
                    let style = Style::default().bg(USER_BG).fg(TEXT);
                    lines.push(Line::from(fill.clone()).style(style));
                    push_wrapped(&mut lines, text, width.saturating_sub(2), style, " ", true);
                    lines.push(Line::from(fill.clone()).style(style));
                }
                Message::Assistant {
                    text, tool_calls, ..
                } => {
                    let style = Style::default().fg(TEXT);
                    if !text.is_empty() {
                        push_wrapped(&mut lines, text, width.saturating_sub(1), style, " ", false);
                    }
                    for call in tool_calls {
                        if !text.is_empty() {
                            lines.push(Line::from(""));
                        }
                        push_tool_header(&mut lines, &call.name, &call.arguments, width);
                    }
                    in_tool_group = !tool_calls.is_empty();
                }
                Message::Tool { content, .. } => {
                    push_tool_output(&mut lines, content, width);
                    in_tool_group = true;
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

const MAX_TOOL_PREVIEW_LINES: usize = 8;

fn tool_verb(name: &str) -> &'static str {
    match name {
        "read_file" => "Read",
        "edit_file" => "Edited",
        "write_file" => "Wrote",
        "list_dir" => "Listed",
        "grep" => "Searched",
        "run_command" => "Ran",
        _ => "Called",
    }
}

fn tool_detail(name: &str, arguments: &str) -> String {
    let args = serde_json::from_str::<serde_json::Value>(arguments).unwrap_or_default();
    let field = |key: &str| {
        args.get(key)
            .and_then(serde_json::Value::as_str)
            .map(str::to_string)
    };
    let detail = match name {
        "run_command" => field("command"),
        "grep" => field("pattern"),
        _ => field("path"),
    };
    detail.unwrap_or_else(|| arguments.chars().take(200).collect())
}

fn push_tool_header(lines: &mut Vec<Line<'static>>, name: &str, arguments: &str, width: usize) {
    let verb = tool_verb(name);
    let detail = tool_detail(name, arguments);
    let detail = detail.replace('\n', " ");
    let head = if verb == "Called" {
        format!("{verb} {name} {detail}")
    } else {
        format!("{verb} {detail}")
    };
    let available = width.saturating_sub(4).max(1);
    let mut chunks = wrap_text(&head, available).into_iter();
    let first = chunks.next().unwrap_or_default();
    lines.push(Line::from(vec![
        Span::styled(" • ", Style::default().fg(MUTED)),
        Span::styled(
            first,
            Style::default().fg(TEXT).add_modifier(Modifier::BOLD),
        ),
    ]));
    for chunk in chunks {
        lines.push(Line::from(Span::styled(
            format!("   {chunk}"),
            Style::default().fg(TEXT),
        )));
    }
}

fn push_tool_output(lines: &mut Vec<Line<'static>>, content: &str, width: usize) {
    let failed = content.starts_with("error:") || content.starts_with("denied:");
    let style = if failed {
        Style::default().fg(Color::Red)
    } else {
        Style::default().fg(MUTED)
    };
    let available = width.saturating_sub(5).max(1);
    let mut wrapped: Vec<String> = Vec::new();
    for raw in content.lines() {
        wrapped.extend(wrap_text(raw, available));
    }
    let omitted = wrapped.len().saturating_sub(MAX_TOOL_PREVIEW_LINES);
    for (index, chunk) in wrapped.iter().take(MAX_TOOL_PREVIEW_LINES).enumerate() {
        let prefix = if index == 0 { "   └ " } else { "     " };
        lines.push(Line::from(Span::styled(format!("{prefix}{chunk}"), style)));
    }
    if omitted > 0 {
        lines.push(Line::from(Span::styled(
            format!("     … +{omitted} lines"),
            Style::default().fg(MUTED).add_modifier(Modifier::DIM),
        )));
    }
}
