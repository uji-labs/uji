use std::cell::RefCell;
use std::rc::Rc;

use ratatui::prelude::*;
use ratatui::style::Modifier;
use ratatui::symbols;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};
use uji_core::session::model::{Message, StoredMessage};

use crate::app::App;
use crate::model::{self, Border, BufferKind, WindowSpec};
use crate::state::UiState;

const USER_BG: Color = Color::Rgb(0x34, 0x35, 0x41);
const TEXT: Color = Color::Rgb(0xd4, 0xd4, 0xd4);
const MUTED: Color = Color::Rgb(0x80, 0x80, 0x80);

pub fn render(frame: &mut Frame<'_>, app: &App) {
    let state: Rc<RefCell<UiState>> = app.state().clone();
    let state = state.borrow();
    render_node(frame, app, &state, Node::Root, frame.area());
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
            let block = block_for(window);
            let inner = block.as_ref().map_or(area, |b| b.inner(area));
            let kind = state
                .buffer_kind(&window.buffer)
                .unwrap_or(BufferKind::Messages);

            let paragraph = match kind {
                BufferKind::Messages => {
                    Paragraph::new(render_messages(app.messages(), app.pending(), inner.width))
                }
                BufferKind::Input => Paragraph::new(render_input(app, state)),
            };
            let paragraph = match block {
                Some(block) => paragraph.block(block),
                None => paragraph,
            };
            frame.render_widget(paragraph, area);
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
