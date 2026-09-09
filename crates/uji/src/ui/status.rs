use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::Paragraph;

use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::MUTED;

pub(crate) struct Status;

impl Render for Status {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let segments: Vec<&str> = ctx.state.footer().iter().map(String::as_str).collect();
        let text = if segments.is_empty() {
            ctx.state.opts().footer_hint.clone()
        } else {
            format!(
                "{} · {}",
                segments.join(" · "),
                ctx.state.opts().footer_hint
            )
        };
        surface.render_widget(Paragraph::new(Line::styled(
            text,
            Style::default().fg(MUTED),
        )));
    }
}
