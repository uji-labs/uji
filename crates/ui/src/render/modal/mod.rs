use ratatui::style::Style;
use ratatui::text::Span;

use crate::app::{Line, Mode};
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
pub(crate) fn typed(line: &Line, hidden: bool, text: Style, cursor: Style) -> Vec<Span<'static>> {
    let at = line
        .text()
        .get(..line.cursor())
        .map_or(0, |before| before.chars().count());
    let shown: Vec<char> = if hidden {
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
