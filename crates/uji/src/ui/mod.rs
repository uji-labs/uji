use ratatui::Frame;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::text::Line as TLine;
use ratatui::widgets::{Paragraph, Widget};
use uji_api::model::{Builtin, Size, WindowSpec};
use uji_api::state::UiState;

use crate::app::App;

pub(crate) mod buffer;
pub(crate) mod input;
pub(crate) mod layout;
pub(crate) mod messages;
pub(crate) mod modal;
pub(crate) mod style;
pub(crate) mod wrap;

pub struct Context<'a> {
    pub app: &'a App,
    pub state: &'a UiState,
}

pub struct Surface<'a> {
    area: Rect,
    buf: &'a mut Buffer,
}

impl<'a> Surface<'a> {
    pub fn new(area: Rect, buf: &'a mut Buffer) -> Self {
        Self { area, buf }
    }

    pub fn area(&self) -> Rect {
        self.area
    }

    pub fn buf(&mut self) -> &mut Buffer {
        &mut *self.buf
    }

    pub fn render_widget(&mut self, widget: impl Widget) {
        widget.render(self.area, self.buf);
    }

    pub fn render_at(&mut self, area: Rect, widget: impl Widget) {
        widget.render(area, self.buf);
    }
}

pub trait Render {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>);
}

pub fn render(frame: &mut Frame<'_>, app: &App) {
    let state = app.state();
    let fit = input_fit(frame.area(), &state.borrow(), app.input());
    if let Some((id, height)) = fit {
        state.borrow_mut().set_window_size(id, Size::Fixed(height));
    }
    let rects = {
        let s = state.borrow();
        layout::layout(frame.area(), s.windows())
    };
    let s = state.borrow();
    let input_rect = s
        .windows()
        .iter()
        .zip(rects.iter().copied())
        .find(|(window, _)| window.builtin == Some(Builtin::Input))
        .map(|(_, rect)| rect);
    let ctx = Context { app, state: &s };
    for (window, rect) in s.windows().iter().zip(rects.iter().copied()) {
        let mut surface = Surface::new(rect, frame.buffer_mut());
        match window.builtin {
            Some(Builtin::Messages) => {
                messages::Messages { window }.render(&ctx, &mut surface);
            }
            Some(Builtin::Input) => {
                input::Input { window }.render(&ctx, &mut surface);
            }
            None => blit(&mut surface, window),
        }
    }
    let mut surface = Surface::new(frame.area(), frame.buffer_mut());
    modal::Modal { input_rect }.render(&ctx, &mut surface);
}

const MAX_INPUT_ROWS: u16 = 10;

fn input_fit(area: Rect, state: &UiState, input: &str) -> Option<(u32, u16)> {
    let rects = layout::layout(area, state.windows());
    let (window, rect) = state
        .windows()
        .iter()
        .zip(rects)
        .find(|(window, _)| window.builtin == Some(Builtin::Input))?;
    let Size::Fixed(current) = window.opts.size else {
        return None;
    };
    let inner = style::block_for(window).map_or(rect, |block| block.inner(rect));
    if inner.width == 0 {
        return None;
    }
    let rows = input::rows_needed(input, usize::from(inner.width));
    let rows = u16::try_from(rows)
        .unwrap_or(MAX_INPUT_ROWS)
        .clamp(1, MAX_INPUT_ROWS);
    let border = rect.height.saturating_sub(inner.height);
    let wanted = rows.saturating_add(border);
    (wanted != current).then_some((window.id, wanted))
}

fn blit(surface: &mut Surface<'_>, window: &WindowSpec) {
    let block = style::block_for(window);
    let inner = block
        .as_ref()
        .map_or(surface.area(), |block| block.inner(surface.area()));
    let width = usize::from(inner.width);
    let mut lines: Vec<TLine<'static>> = Vec::new();
    for line in &window.buffer {
        if window.opts.wrap {
            for wrapped in buffer::wrap_line(line, width) {
                lines.push(buffer::line_to_ratatui(&wrapped, width));
            }
        } else {
            lines.push(buffer::line_to_ratatui(line, width));
        }
    }
    let paragraph = Paragraph::new(lines);
    match block {
        Some(block) => surface.render_widget(paragraph.block(block)),
        None => surface.render_widget(paragraph),
    }
}
