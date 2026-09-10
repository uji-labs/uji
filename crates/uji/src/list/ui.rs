use std::io;

use crossterm::event;
use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use ratatui::layout::{Constraint, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Cell, Paragraph, Row, Table};

use crate::app::{self, Term};
use crate::session::id::now_millis;
use crate::session::model::Session;
use crate::ui::style::{MUTED, SELECTED_BG, TEXT};

pub(super) struct State {
    cursor: usize,
    selected: Option<usize>,
    running: bool,
}

pub(super) fn pick(sessions: &[Session], current_dir: &str) -> io::Result<Option<usize>> {
    let mut terminal = app::setup()?;
    let mut state = State {
        cursor: 0,
        selected: None,
        running: true,
    };

    let result = run_loop(&mut terminal, sessions, current_dir, &mut state);
    let restore = app::restore(&mut terminal);

    match (result, restore) {
        (Ok(()), Ok(())) => Ok(state.selected),
        (Err(err), _) | (_, Err(err)) => Err(err),
    }
}

fn run_loop(
    terminal: &mut Term,
    sessions: &[Session],
    current_dir: &str,
    state: &mut State,
) -> io::Result<()> {
    draw(terminal, sessions, current_dir, state)?;
    while state.running {
        if let Event::Key(key) = event::read()? {
            handle_key(key, sessions.len(), state);
            if !state.running {
                break;
            }
        }
        draw(terminal, sessions, current_dir, state)?;
    }
    Ok(())
}

fn handle_key(key: KeyEvent, sessions_len: usize, state: &mut State) {
    if key.kind == KeyEventKind::Release {
        return;
    }

    match key.code {
        KeyCode::Up => {
            state.cursor = state.cursor.saturating_sub(1);
        }
        KeyCode::Down => {
            state.cursor = state
                .cursor
                .saturating_add(1)
                .min(sessions_len.saturating_sub(1));
        }
        KeyCode::PageUp => {
            state.cursor = state.cursor.saturating_sub(10);
        }
        KeyCode::PageDown => {
            state.cursor = state
                .cursor
                .saturating_add(10)
                .min(sessions_len.saturating_sub(1));
        }
        KeyCode::Home => {
            state.cursor = 0;
        }
        KeyCode::End => {
            state.cursor = sessions_len.saturating_sub(1);
        }
        KeyCode::Enter => {
            if sessions_len > 0 {
                state.selected = Some(state.cursor);
                state.running = false;
            }
        }
        KeyCode::Esc => {
            state.running = false;
        }
        KeyCode::Char('q') if key.modifiers == KeyModifiers::NONE => {
            state.running = false;
        }
        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            state.running = false;
        }
        _ => {}
    }
}

fn draw(
    terminal: &mut Term,
    sessions: &[Session],
    current_dir: &str,
    state: &State,
) -> io::Result<()> {
    terminal.draw(|frame| {
        let [list_area, footer_area] =
            Layout::vertical([Constraint::Fill(1), Constraint::Length(1)]).areas(frame.area());

        let title = format!(" Sessions in {current_dir} ");
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Cyan))
            .title(title);
        let inner = block.inner(list_area);
        let available = usize::from(inner.height).saturating_sub(1);

        let header = Row::new(["TITLE", "UPDATED", "ID"])
            .style(Style::default().fg(MUTED).add_modifier(Modifier::BOLD));

        let rows = if sessions.is_empty() {
            vec![
                Row::new([
                    Cell::from(""),
                    Cell::from("No sessions in current directory"),
                    Cell::from(""),
                ])
                .style(Style::default().fg(MUTED)),
            ]
        } else {
            let start = visible_start(state.cursor, sessions.len(), available);
            let end = (start + available).min(sessions.len());
            let cursor_in_view = state.cursor - start;

            sessions[start..end]
                .iter()
                .enumerate()
                .map(|(index, session)| {
                    let style = if index == cursor_in_view {
                        Style::default().bg(SELECTED_BG)
                    } else {
                        Style::default()
                    };
                    Row::new([
                        Cell::from(session.title.clone()),
                        Cell::from(format_when(session.time.updated)),
                        Cell::from(session.id.to_string()),
                    ])
                    .style(style)
                })
                .collect()
        };

        let table = Table::new(
            rows,
            [
                Constraint::Fill(1),
                Constraint::Length(14),
                Constraint::Length(36),
            ],
        )
        .header(header)
        .block(block)
        .column_spacing(2)
        .style(Style::default().fg(TEXT));

        frame.render_widget(table, list_area);

        let hint = if sessions.is_empty() {
            Line::from(vec![
                Span::styled("esc", Style::default().fg(Color::Cyan)),
                Span::styled(" quit", Style::default().fg(MUTED)),
            ])
        } else {
            Line::from(vec![
                Span::styled("↑/↓", Style::default().fg(Color::Cyan)),
                Span::styled(" navigate   ", Style::default().fg(MUTED)),
                Span::styled("enter", Style::default().fg(Color::Cyan)),
                Span::styled(" resume   ", Style::default().fg(MUTED)),
                Span::styled("esc", Style::default().fg(Color::Cyan)),
                Span::styled(" quit", Style::default().fg(MUTED)),
            ])
        };
        frame.render_widget(Paragraph::new(hint), footer_area);
    })?;
    Ok(())
}

fn visible_start(cursor: usize, len: usize, available: usize) -> usize {
    let available = available.max(1);
    let max_start = len.saturating_sub(available);
    if cursor < available {
        0
    } else {
        cursor.saturating_sub(available - 1).min(max_start)
    }
}

fn format_when(updated: i64) -> String {
    let delta = now_millis().saturating_sub(updated);
    let seconds = delta / 1000;

    if seconds < 60 {
        "just now".into()
    } else if seconds < 3_600 {
        format!("{}m ago", seconds / 60)
    } else if seconds < 86_400 {
        format!("{}h ago", seconds / 3_600)
    } else if seconds < 7 * 86_400 {
        format!("{}d ago", seconds / 86_400)
    } else {
        let days = seconds / 86_400;
        if days < 365 {
            format!("{days}d ago")
        } else {
            format!("{}y ago", days / 365)
        }
    }
}
