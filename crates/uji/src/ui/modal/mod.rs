use ratatui::layout::Rect;

use crate::app::Mode;
use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;

mod menu;
mod prompt;
mod select;
mod suggest;

pub(crate) struct Modal {
    pub(crate) input_rect: Option<Rect>,
}

impl Render for Modal {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        match ctx.app.mode() {
            Mode::Normal | Mode::Confirm { .. } => {}
            Mode::Select {
                title,
                items,
                cursor,
            } => {
                select::Select {
                    title,
                    items,
                    cursor: *cursor,
                }
                .render(ctx, surface);
            }
            Mode::Prompt {
                title,
                value,
                secret,
            } => {
                prompt::Prompt {
                    title,
                    value,
                    secret: *secret,
                }
                .render(ctx, surface);
            }
            Mode::Suggest { items, cursor } => {
                suggest::Suggest {
                    items,
                    cursor: *cursor,
                    input_rect: self.input_rect,
                }
                .render(ctx, surface);
            }
        }
    }
}
