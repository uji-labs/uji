use ratatui::style::Style;
use ratatui::text::Span;

use crate::app::{Echo, Line, Mode};
use crate::render::Context;
use crate::render::Render;
use crate::render::Surface;

pub(crate) mod confirm;
mod pick;
mod prompt;
mod select;
mod suggest;

pub(crate) struct Modal;

const CURSOR: &str = "\u{2588}";

/// A typed line with the cursor block drawn where the cursor actually is.
///
/// Prompts and queries are edited with the same keys as the composer, so they
/// have to show the same thing the composer shows: a cursor that can sit in the
/// middle of the text.
pub(crate) fn typed(line: &Line, echo: Echo, text: Style, cursor: Style) -> Vec<Span<'static>> {
    let at = line
        .text()
        .get(..line.cursor())
        .map_or(0, |before| before.chars().count());
    let shown: Vec<char> = if echo == Echo::Hidden {
        std::iter::repeat_n('\u{2022}', line.text().chars().count()).collect()
    } else {
        line.text().chars().collect()
    };
    vec![
        Span::styled(shown.iter().take(at).collect::<String>(), text),
        Span::styled(CURSOR, cursor),
        Span::styled(shown.iter().skip(at).collect::<String>(), text),
    ]
}

pub(crate) fn rows(ctx: &Context<'_>, _width: u16) -> Option<u16> {
    match ctx.app.mode() {
        // Confirm takes over the frame; a picker draws into its own float.
        // Neither claims strip rows.
        Mode::Normal | Mode::Confirm { .. } | Mode::Pick { .. } => None,
        Mode::Select { matches, .. } => {
            let matches = matches.len();
            let visible = matches.min(select::MAX_ROWS);
            let overflow = u16::from(matches > visible);
            let rows = u16::try_from(visible).unwrap_or(u16::MAX);
            Some(rows.saturating_add(4).saturating_add(overflow))
        }
        Mode::Prompt { .. } => Some(prompt::ROWS),
        Mode::Suggest { items, .. } => {
            let max = usize::from(ctx.state.opts().suggest_max_height).max(1);
            let visible = items.len().min(max);
            u16::try_from(visible).ok().filter(|rows| *rows > 0)
        }
    }
}

pub(crate) fn takeover_rows(ctx: &Context<'_>, width: u16) -> Option<u16> {
    match ctx.app.mode() {
        Mode::Confirm { title, body, .. } => Some(confirm::rows(ctx, title, body, width)),
        _ => None,
    }
}

impl Render for Modal {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        match ctx.app.mode() {
            Mode::Normal | Mode::Confirm { .. } => {}
            Mode::Select {
                title,
                items,
                query,
                cursor,
                matches,
            } => {
                select::Select {
                    title,
                    items,
                    query,
                    cursor: *cursor,
                    matches,
                }
                .render(ctx, surface);
            }
            Mode::Pick {
                title,
                items,
                query,
                cursor,
                matches,
                preview,
                ..
            } => {
                pick::Pick {
                    title,
                    items,
                    query,
                    cursor: *cursor,
                    matches,
                    preview,
                }
                .render(ctx, surface);
            }
            Mode::Prompt { title, value, echo } => {
                prompt::Prompt {
                    title,
                    value,
                    echo: *echo,
                }
                .render(ctx, surface);
            }
            Mode::Suggest { items, cursor } => {
                suggest::Suggest {
                    items,
                    cursor: *cursor,
                }
                .render(ctx, surface);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use ratatui::buffer::Buffer;
    use ratatui::layout::Rect;
    use ratatui::style::Style;

    use std::cell::RefCell;
    use std::rc::Rc;

    use uji_agent::session::conversation::Conversation;
    use uji_agent::session::id::SessionId;
    use uji_agent::session::model::{Session, Time};

    use crate::app::{App, Echo, Line};
    use crate::render::style::Palette;
    use crate::render::{Context, Render, Surface};
    use crate::state::UiState;

    fn line(text: &str, cursor: usize) -> Line {
        let mut line = Line::default();
        line.set(String::from(text));
        for _ in 0..line.text().len().saturating_sub(cursor) {
            line.left();
        }
        line
    }

    fn drawn(spans: &[ratatui::text::Span<'static>]) -> String {
        spans.iter().map(|span| span.content.as_ref()).collect()
    }

    #[test]
    fn the_cursor_is_drawn_where_the_cursor_is() {
        let spans = super::typed(
            &line("abcd", 2),
            Echo::Plain,
            Style::default(),
            Style::default(),
        );
        assert_eq!(drawn(&spans), "ab\u{2588}cd");
    }

    /// A hidden prompt is how an API key is typed in. It must never render the
    /// characters, at any cursor position.
    #[test]
    fn a_hidden_prompt_shows_no_characters() {
        let spans = super::typed(
            &line("s3cret", 3),
            Echo::Hidden,
            Style::default(),
            Style::default(),
        );
        let shown = drawn(&spans);
        assert_eq!(
            shown,
            "\u{2022}\u{2022}\u{2022}\u{2588}\u{2022}\u{2022}\u{2022}"
        );
        assert!(!shown.contains("s3cret"));
        assert!(!shown.contains('3'));
    }

    /// The whole prompt modal, not just its line: an empty draw would leave the
    /// user typing into nothing.
    #[test]
    fn the_prompt_modal_draws_its_title_and_value() {
        let session = Session {
            id: SessionId::new(),
            parent_id: None,
            title: String::new(),
            directory: String::from("."),
            time: Time {
                created: 0,
                updated: 0,
            },
        };
        let app = App::new(
            session,
            Conversation::shared(),
            Rc::new(RefCell::new(UiState::new())),
        );
        let state = UiState::new();
        let ctx = Context {
            app: &app,
            state: &state,
            palette: Palette::default(),
        };
        let area = Rect::new(0, 0, 40, 6);
        let mut buffer = Buffer::empty(area);
        let mut surface = Surface::new(area, &mut buffer);
        let value = line("hunter2", 7);
        let prompt = super::prompt::Prompt {
            title: "api key",
            value: &value,
            echo: Echo::Hidden,
        };
        prompt.render(&ctx, &mut surface);
        let text: String = buffer
            .content()
            .iter()
            .map(ratatui::buffer::Cell::symbol)
            .collect();
        assert!(text.contains("api key"), "the title should be drawn");
        assert!(text.contains('\u{2022}'), "the value should be masked");
        assert!(!text.contains("hunter2"));
    }
}
