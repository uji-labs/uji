use ratatui::prelude::*;
use ratatui::style::Modifier;
use ratatui::symbols;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Paragraph};
use uji_core::session::model::{Message, StoredMessage};

use crate::app::{App, Mode};
use crate::model::{self, Border, BufferKind, WindowSpec};
use crate::state::UiState;

const USER_BG: Color = Color::Rgb(0x34, 0x35, 0x41);
const TEXT: Color = Color::Rgb(0xd4, 0xd4, 0xd4);
const MUTED: Color = Color::Rgb(0x80, 0x80, 0x80);
const SELECTED_BG: Color = Color::Rgb(0x3a, 0x3a, 0x4a);

pub fn render(frame: &mut Frame<'_>, app: &App) {
    let input_rect = {
        let state = app.state().borrow();
        let rects = model::layout(frame.area(), state.windows());
        state
            .windows()
            .iter()
            .zip(rects)
            .find(|(window, _)| state.buffer_kind(&window.buffer) == Some(BufferKind::Input))
            .map(|(_, rect)| rect)
    };
    {
        let state = app.state().borrow();
        render_node(frame, app, &state, Node::Root, frame.area());
    }
    render_modal(frame, app, input_rect);
}

#[derive(Clone, Copy)]
enum Node<'a> {
    Root,
    Window(&'a WindowSpec),
}

fn render_node(frame: &mut Frame<'_>, app: &App, state: &UiState, node: Node<'_>, area: Rect) {
    match node {
        Node::Root => {
            let rects = model::layout(area, state.windows());
            for (window, rect) in state.windows().iter().zip(rects) {
                render_node(frame, app, state, Node::Window(window), rect);
            }
        }
        Node::Window(window) => {
            let kind = state
                .buffer_kind(&window.buffer)
                .unwrap_or(BufferKind::Messages);

            match kind {
                BufferKind::Messages => {
                    let block = block_for(window);
                    let inner = block.as_ref().map_or(area, |b| b.inner(area));
                    let paragraph =
                        Paragraph::new(render_messages(app.messages(), app.pending(), inner.width));
                    let paragraph = match block {
                        Some(block) => paragraph.block(block),
                        None => paragraph,
                    };
                    frame.render_widget(paragraph, area);
                }
                BufferKind::Input => {
                    let block = Block::default().borders(Borders::TOP | Borders::BOTTOM);
                    let paragraph = Paragraph::new(render_input(app, state)).block(block);
                    frame.render_widget(paragraph, area);
                }
                BufferKind::Status => {
                    frame.render_widget(Paragraph::new(render_status(app, state)), area);
                }
            }
        }
    }
}

fn block_for(win: &WindowSpec) -> Option<Block<'static>> {
    let mut block = match win.opts.border {
        Border::None => return None,
        Border::Plain => Block::default().borders(Borders::ALL),
        Border::Rounded => Block::default()
            .borders(Borders::ALL)
            .border_set(symbols::border::ROUNDED),
    };
    if let Some(title) = &win.opts.title {
        block = block.title(title.clone());
    }
    Some(block)
}

fn render_messages(
    messages: &[StoredMessage],
    pending: Option<&str>,
    width: u16,
) -> Vec<Line<'static>> {
    let fill = " ".repeat(usize::from(width));
    let mut lines = Vec::new();
    for stored in messages {
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
        }
    }
    if let Some(pending) = pending.filter(|text| !text.is_empty()) {
        lines.push(Line::from(""));
        let text_style = Style::default().fg(TEXT);
        for line in pending.lines() {
            lines.push(Line::from(format!(" {line}")).style(text_style));
        }
    }
    lines
}

fn render_input(app: &App, state: &UiState) -> Line<'static> {
    let cursor_offset = app.cursor_offset();
    let before = &app.input()[..cursor_offset];
    let after = app.input()[cursor_offset..].to_owned();

    let mut cursor_style = Style::default();
    if state.opts().cursor_blink {
        cursor_style = cursor_style.add_modifier(Modifier::SLOW_BLINK);
    }
    let cursor = Span::styled("█", cursor_style);

    Line::from(vec![Span::raw(before.to_owned()), cursor, Span::raw(after)])
}

fn render_status(app: &App, state: &UiState) -> Line<'static> {
    let text = if app.status().is_empty() {
        state.opts().footer_hint.clone()
    } else {
        format!("{} · {}", app.status(), state.opts().footer_hint)
    };
    Line::styled(text, Style::default().fg(MUTED))
}

fn render_modal(frame: &mut Frame<'_>, app: &App, input_rect: Option<Rect>) {
    match app.mode() {
        Mode::Normal => {}
        Mode::Select {
            title,
            items,
            cursor,
        } => {
            let height = u16::try_from(items.len()).unwrap_or(1).saturating_add(4);
            let area = centered_rect(frame.area(), 64, height);
            frame.render_widget(Clear, area);
            let lines: Vec<Line<'_>> = items
                .iter()
                .enumerate()
                .map(|(i, item)| {
                    if i == *cursor {
                        Line::styled(format!("> {item}"), Style::default().fg(Color::Cyan))
                    } else {
                        Line::raw(format!("  {item}"))
                    }
                })
                .collect();
            let block = Block::default().borders(Borders::ALL).title(title.as_str());
            frame.render_widget(Paragraph::new(lines).block(block), area);
        }
        Mode::Prompt {
            title,
            value,
            secret,
        } => {
            let area = centered_rect(frame.area(), 64, 3);
            frame.render_widget(Clear, area);
            let shown = if *secret {
                "•".repeat(value.chars().count())
            } else {
                value.clone()
            };
            let block = Block::default().borders(Borders::ALL).title(title.as_str());
            frame.render_widget(Paragraph::new(format!("{shown} █")).block(block), area);
        }
        Mode::Suggest { items, cursor } => {
            let Some(input_rect) = input_rect else {
                return;
            };
            if items.is_empty() {
                return;
            }
            let max = usize::from(app.state().borrow().opts().suggest_max_height).max(1);
            let visible = items.len().min(max);
            let start = if *cursor >= visible {
                cursor.saturating_sub(visible - 1)
            } else {
                0
            };
            let window = &items[start..(start + visible).min(items.len())];
            let cursor_in_window = cursor - start;

            let height = u16::try_from(window.len()).unwrap_or(1);
            let area = Rect {
                x: input_rect.x,
                y: input_rect.y.saturating_sub(height),
                width: input_rect.width,
                height,
            };
            frame.render_widget(Clear, area);
            let lines: Vec<Line<'_>> = window
                .iter()
                .enumerate()
                .map(|(i, item)| {
                    let selected = i == cursor_in_window;
                    let row = if selected {
                        Style::default().bg(SELECTED_BG)
                    } else {
                        Style::default()
                    };
                    let name = Span::styled(
                        format!(" {:<12}", item.name),
                        if selected {
                            Style::default().fg(Color::Cyan)
                        } else {
                            Style::default().fg(TEXT)
                        },
                    );
                    let desc = Span::styled(item.desc.clone(), Style::default().fg(MUTED));
                    Line::from(vec![name, desc]).style(row)
                })
                .collect();
            frame.render_widget(Paragraph::new(lines), area);
        }
    }
}

fn centered_rect(area: Rect, width: u16, height: u16) -> Rect {
    let x = area.x + area.width.saturating_sub(width) / 2;
    let y = area.y + area.height.saturating_sub(height) / 2;
    Rect {
        x,
        y,
        width: width.min(area.width),
        height: height.min(area.height),
    }
}
