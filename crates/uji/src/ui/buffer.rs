use ratatui::style::{Color, Style as TStyle};
use ratatui::text::{Line as TLine, Span as TSpan};
use uji_api::model::{Line, Span, Style};

use super::style;

pub(crate) fn line_to_ratatui(line: &Line, width: usize) -> TLine<'static> {
    let bg = uniform_bg(&line.spans);
    let text_width: usize = line
        .spans
        .iter()
        .map(|span| span.text.chars().count())
        .sum();
    let mut spans: Vec<TSpan<'static>> = line
        .spans
        .iter()
        .map(|span| TSpan::styled(span.text.clone(), style::span_style(&span.style)))
        .collect();
    if let Some(bg) = bg
        && text_width < width
    {
        spans.push(TSpan::styled(
            " ".repeat(width - text_width),
            TStyle::default().bg(bg),
        ));
    }
    TLine::from(spans)
}

pub(crate) fn wrap_line(line: &Line, width: usize) -> Vec<Line> {
    if width == 0 || line.spans.is_empty() {
        return vec![line.clone()];
    }
    let mut chars: Vec<(char, Style)> = Vec::new();
    for span in &line.spans {
        for ch in span.text.chars() {
            chars.push((ch, span.style));
        }
    }
    let mut lines = Vec::new();
    let mut current: Vec<(char, Style)> = Vec::new();
    for (ch, style) in chars {
        if current.len() >= width {
            if let Some(pos) = current.iter().rposition(|&(c, _)| c == ' ') {
                let rest = current.split_off(pos + 1);
                lines.push(coalesce(std::mem::take(&mut current)));
                current = rest;
            } else {
                lines.push(coalesce(std::mem::take(&mut current)));
            }
        }
        current.push((ch, style));
    }
    if !current.is_empty() {
        lines.push(coalesce(current));
    }
    if lines.is_empty() {
        lines.push(line.clone());
    }
    lines
}

fn coalesce(chars: Vec<(char, Style)>) -> Line {
    let mut spans: Vec<Span> = Vec::new();
    let mut current_style: Option<Style> = None;
    let mut text = String::new();
    for (ch, style) in chars {
        if Some(style) != current_style {
            if !text.is_empty() {
                spans.push(Span::styled(
                    std::mem::take(&mut text),
                    current_style.unwrap_or_default(),
                ));
            }
            current_style = Some(style);
        }
        text.push(ch);
    }
    if !text.is_empty() {
        spans.push(Span::styled(text, current_style.unwrap_or_default()));
    }
    Line { spans }
}

fn uniform_bg(spans: &[Span]) -> Option<Color> {
    let mut bg = None;
    for span in spans {
        match style::span_background(&span.style) {
            None => return None,
            Some(color) => match bg {
                None => bg = Some(color),
                Some(prev) if prev != color => return None,
                Some(_) => {}
            },
        }
    }
    bg
}
