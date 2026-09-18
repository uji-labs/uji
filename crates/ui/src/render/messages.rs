use crate::model::WindowSpec;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};

use crate::app::renderer::Block;
use crate::render::Context;
use crate::render::Render;
use crate::render::Surface;
use crate::render::style::{Palette, block_for};
use crate::render::transcript;
use crate::render::wrap::text as wrap_text;
use uji_agent::session::model::{Message, StoredMessage};

pub(crate) struct Messages<'a> {
    pub(crate) window: &'a WindowSpec,
}

impl Render for Messages<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let palette = ctx.palette;
        let block = block_for(self.window, palette);
        let inner = block
            .as_ref()
            .map_or(surface.area(), |b| b.inner(surface.area()));
        let width = usize::from(inner.width);
        let height = usize::from(inner.height);

        let renderer = ctx.app.renderer();
        let conversation = ctx.app.messages();
        let pending = ctx.app.pending().unwrap_or_default();
        let (committed, partial) = split_committed(pending);
        let mut transcript = ctx.app.transcript();
        let split = !renderer.is_some_and(|renderer| renderer.overrides());
        let parts = transcript.frame(
            &transcript::Input {
                conversation: &conversation,
                notices: ctx.app.overlay().notices(),
                queued: ctx.app.overlay().queued(),
                thinking: ctx.state.opts().show_thinking,
                pending: committed,
                width,
                palette,
            },
            split,
            |lines, block, width| match renderer.and_then(|renderer| renderer.render(block)) {
                Some(custom) => push_custom(lines, &custom, width),
                None => push_builtin(lines, block, width, palette),
            },
        );

        let mut gap = Vec::new();
        if !parts.notices.is_empty() {
            gap.push(Line::from(""));
        }
        let above = parts
            .notices
            .len()
            .saturating_add(gap.len())
            .saturating_add(parts.folded.len());

        let mut lead = Vec::new();
        if !pending.is_empty() && above > 0 {
            lead.push(Line::from(""));
        }
        let mut tail = Vec::new();
        if !partial.is_empty() {
            push_wrapped(
                &mut tail,
                partial,
                width,
                Style::default().fg(palette.text),
                " ",
                Fill::Line,
            );
        }

        let mut queued = Vec::new();
        if let Some((name, output)) = ctx.app.overlay().running() {
            queued.push(Line::from(""));
            push_wrapped(
                &mut queued,
                &format!("{name}  {output}"),
                width,
                Style::default()
                    .fg(palette.muted)
                    .add_modifier(Modifier::DIM),
                " ⋯ ",
                Fill::Line,
            );
        }
        if !parts.queued.is_empty() {
            queued.push(Line::from(""));
            queued.extend(parts.queued.iter().cloned());
        }

        let body_height = height.saturating_sub(queued.len());
        let total = above
            .saturating_add(lead.len())
            .saturating_add(parts.pending_len())
            .saturating_add(tail.len());
        let start = ctx
            .app
            .resolve_scroll(total.saturating_sub(body_height), body_height);
        let end = start.saturating_add(body_height).min(total);
        if let Some(block) = block {
            surface.render_widget(block);
        }
        let visible = parts
            .notices
            .iter()
            .chain(gap.iter())
            .chain(parts.folded.iter())
            .chain(lead.iter())
            .chain(parts.settled.iter())
            .chain(parts.open.iter())
            .chain(tail.iter())
            .skip(start)
            .take(end.saturating_sub(start))
            .chain(queued.iter());
        crate::render::write_lines(surface, inner, visible);
    }
}

fn push_builtin(lines: &mut Vec<Line<'static>>, block: Block<'_>, width: usize, palette: Palette) {
    match block {
        Block::Notice(text) => push_wrapped(
            lines,
            text,
            width,
            Style::default().fg(palette.notice),
            " ! ",
            Fill::Line,
        ),
        Block::Message(stored) => push_message(lines, stored, width, palette),
        Block::Pending { text, continuing } => {
            push_markdown(lines, text, width, palette, continuing);
        }
        Block::Thinking(text) => push_wrapped(
            lines,
            text,
            width,
            Style::default()
                .fg(palette.muted)
                .add_modifier(Modifier::ITALIC | Modifier::DIM),
            " │ ",
            Fill::Line,
        ),
        Block::Queued(text) => push_wrapped(
            lines,
            text,
            width,
            Style::default()
                .fg(palette.muted)
                .add_modifier(Modifier::DIM),
            " › ",
            Fill::Line,
        ),
    }
}

fn push_custom(lines: &mut Vec<Line<'static>>, custom: &[crate::model::Line], width: usize) {
    lines.extend(custom.iter().flat_map(|line| {
        crate::render::buffer::wrap_line(line, width)
            .into_iter()
            .map(|wrapped| crate::render::buffer::line_to_ratatui(&wrapped, width))
    }));
}

pub(crate) fn push_message(
    lines: &mut Vec<Line<'static>>,
    stored: &StoredMessage,
    width: usize,
    palette: Palette,
) {
    match &stored.message {
        Message::User { text } => {
            let style = Style::default().bg(palette.user_bg).fg(palette.text);
            let fill = Line::from(" ".repeat(width)).style(style);
            lines.push(fill.clone());
            push_wrapped(lines, text, width, style, " ", Fill::Block);
            lines.push(fill);
        }
        Message::Assistant {
            text, tool_calls, ..
        } => {
            if !text.is_empty() {
                push_markdown(lines, text, width, palette, false);
            }
            for call in tool_calls {
                if !text.is_empty() {
                    lines.push(Line::from(""));
                }
                push_tool_header(lines, &call.name, &call.arguments, width, palette);
            }
        }
        Message::Tool { content, .. } => push_tool_output(lines, content, width, palette),
        Message::Shell {
            command,
            output,
            code,
        } => {
            let header = if *code == 0 {
                format!("! {command}")
            } else {
                format!("! {command}  (exit {code})")
            };
            push_wrapped(
                lines,
                &header,
                width,
                Style::default()
                    .fg(palette.accent)
                    .add_modifier(Modifier::BOLD),
                " ",
                Fill::Line,
            );
            if !output.is_empty() {
                push_tool_output(lines, output, width, palette);
            }
        }
        Message::System { text } => {
            let style = Style::default()
                .fg(palette.muted)
                .add_modifier(Modifier::ITALIC);
            push_wrapped(lines, text, width, style, " ", Fill::Line);
        }
        Message::Error { text } => {
            push_wrapped(
                lines,
                text,
                width,
                Style::default().fg(palette.error),
                " ",
                Fill::Line,
            );
        }
        Message::Compaction { .. } => push_divider(lines, width, palette),
    }
}

fn push_divider(lines: &mut Vec<Line<'static>>, width: usize, palette: Palette) {
    let label = " compacted ";
    let rule = width.saturating_sub(label.chars().count() + 2) / 2;
    let bar = "─".repeat(rule);
    lines.push(Line::from(Span::styled(
        format!(" {bar}{label}{bar}"),
        Style::default()
            .fg(palette.muted)
            .add_modifier(Modifier::DIM),
    )));
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Fill {
    Line,
    Block,
}

fn push_wrapped(
    lines: &mut Vec<Line<'static>>,
    text: &str,
    width: usize,
    style: Style,
    prefix: &str,
    fill: Fill,
) {
    let trailing = usize::from(fill == Fill::Block);
    let inner = width.saturating_sub(prefix.chars().count() + trailing);
    for chunk in wrap_text(text, inner) {
        let line = match fill {
            Fill::Line => format!("{prefix}{chunk}"),
            Fill::Block => {
                let pad = " ".repeat(inner.saturating_sub(chunk.chars().count()));
                format!("{prefix}{chunk} {pad}")
            }
        };
        lines.push(Line::from(line).style(style));
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

fn push_tool_header(
    lines: &mut Vec<Line<'static>>,
    name: &str,
    arguments: &str,
    width: usize,
    palette: Palette,
) {
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
        Span::styled(" • ", Style::default().fg(palette.muted)),
        Span::styled(
            first,
            Style::default()
                .fg(palette.text)
                .add_modifier(Modifier::BOLD),
        ),
    ]));
    lines.extend(chunks.map(|chunk| {
        Line::from(Span::styled(
            format!("   {chunk}"),
            Style::default().fg(palette.text),
        ))
    }));
}

fn push_tool_output(lines: &mut Vec<Line<'static>>, content: &str, width: usize, palette: Palette) {
    let failed = content.starts_with("error:") || content.starts_with("denied:");
    let style = if failed {
        Style::default().fg(palette.error)
    } else {
        Style::default().fg(palette.muted)
    };
    let available = width.saturating_sub(5).max(1);
    let wrapped: Vec<String> = content
        .lines()
        .flat_map(|raw| wrap_text(raw, available))
        .collect();
    let omitted = wrapped.len().saturating_sub(MAX_TOOL_PREVIEW_LINES);
    for (index, chunk) in wrapped.iter().take(MAX_TOOL_PREVIEW_LINES).enumerate() {
        let prefix = if index == 0 { "   └ " } else { "     " };
        lines.push(Line::from(Span::styled(format!("{prefix}{chunk}"), style)));
    }
    if omitted > 0 {
        lines.push(Line::from(Span::styled(
            format!("     … +{omitted} lines"),
            Style::default()
                .fg(palette.muted)
                .add_modifier(Modifier::DIM),
        )));
    }
}

fn split_committed(pending: &str) -> (&str, &str) {
    match pending.rfind('\n') {
        Some(at) => (&pending[..=at], &pending[at + 1..]),
        None => ("", pending),
    }
}

fn push_markdown(
    lines: &mut Vec<Line<'static>>,
    text: &str,
    width: usize,
    palette: Palette,
    continuing: bool,
) {
    let width = width.saturating_sub(1);
    for mut line in crate::render::markdown::render_from(text, width, palette, continuing) {
        line.spans.insert(0, Span::raw(" "));
        lines.push(line);
    }
}
