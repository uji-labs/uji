use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Clear, Paragraph};

use crate::ui::Context;
use crate::ui::Render;
use crate::ui::Surface;
use crate::ui::style::{MUTED, TEXT, accent_style, color_of};
use crate::ui::wrap::text as wrap;

pub(crate) struct Confirm<'a> {
    pub(crate) title: &'a str,
    pub(crate) body: &'a str,
    pub(crate) allow: bool,
    pub(crate) input_rect: Option<Rect>,
}

impl Render for Confirm<'_> {
    fn render(&self, ctx: &Context<'_>, surface: &mut Surface<'_>) {
        let Some(input_rect) = self.input_rect else {
            return;
        };
        let opts = ctx.state.opts();
        let confirm = &opts.confirm;

        let selected = confirm
            .selected
            .map_or_else(accent_style, |color| Style::default().fg(color_of(color)));
        let unselected = confirm.unselected.map_or_else(
            || Style::default().fg(MUTED),
            |color| Style::default().fg(color_of(color)),
        );
        let title_style = confirm.title_color.map_or_else(
            || Style::default().fg(TEXT).add_modifier(Modifier::BOLD),
            |color| {
                Style::default()
                    .fg(color_of(color))
                    .add_modifier(Modifier::BOLD)
            },
        );
        let body_style = confirm.body_color.map_or_else(
            || Style::default().fg(TEXT),
            |color| Style::default().fg(color_of(color)),
        );

        let width = usize::from(input_rect.width).saturating_sub(2).max(1);
        let mut lines: Vec<Line<'static>> = Vec::new();
        for chunk in wrap(self.title, width) {
            lines.push(Line::from(Span::styled(format!("  {chunk}"), title_style)));
        }
        lines.push(Line::from(""));
        for chunk in wrap(self.body, width) {
            lines.push(Line::from(Span::styled(format!("  {chunk}"), body_style)));
        }
        lines.push(Line::from(""));
        lines.push(option_line(
            1,
            &format!("{}, proceed", confirm.yes),
            "y",
            self.allow,
            selected,
            unselected,
        ));
        lines.push(option_line(
            2,
            &format!("{}, and tell uji what to do differently", confirm.no),
            "esc",
            !self.allow,
            selected,
            unselected,
        ));

        let height = u16::try_from(lines.len()).unwrap_or(u16::MAX);
        let top = input_rect.y.saturating_sub(height);
        let popup = Rect {
            x: input_rect.x,
            y: top,
            width: input_rect.width,
            height: height.min(input_rect.y.max(1)),
        };
        surface.render_at(popup, Clear);
        surface.render_at(popup, Paragraph::new(lines));
    }
}

fn option_line(
    index: usize,
    label: &str,
    key: &str,
    active: bool,
    selected: Style,
    unselected: Style,
) -> Line<'static> {
    let marker = if active { "\u{203a} " } else { "  " };
    let style = if active { selected } else { unselected };
    Line::from(vec![
        Span::styled(marker.to_string(), style),
        Span::styled(format!("{index}. {label}"), style),
        Span::styled(
            format!(" ({key})"),
            Style::default().fg(MUTED).add_modifier(Modifier::DIM),
        ),
    ])
}
