use ratatui::layout::Rect;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BufferKind {
    Messages,
    Input,
    Status,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BufferSpec {
    pub name: String,
    pub kind: BufferKind,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Border {
    #[default]
    None,
    Plain,
    Rounded,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Size {
    Fill,
    Fixed(u16),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Split {
    #[default]
    Top,
    Bottom,
    Left,
    Right,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WinOpts {
    pub split: Split,
    pub size: Size,
    pub border: Border,
    pub title: Option<String>,
}

impl Default for WinOpts {
    fn default() -> Self {
        Self {
            split: Split::Top,
            size: Size::Fill,
            border: Border::None,
            title: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct WindowSpec {
    pub buffer: String,
    pub opts: WinOpts,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GlobalOpts {
    pub cursor_blink: bool,
    pub suggest_enabled: bool,
    pub suggest_max_height: u16,
    pub footer_hint: String,
}

impl Default for GlobalOpts {
    fn default() -> Self {
        Self {
            cursor_blink: true,
            suggest_enabled: true,
            suggest_max_height: 5,
            footer_hint: "ctrl+c exit".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct UiModel {
    pub buffers: Vec<BufferSpec>,
    pub windows: Vec<WindowSpec>,
    pub opts: GlobalOpts,
}

impl Default for UiModel {
    fn default() -> Self {
        Self {
            buffers: vec![
                BufferSpec {
                    name: "messages".into(),
                    kind: BufferKind::Messages,
                },
                BufferSpec {
                    name: "input".into(),
                    kind: BufferKind::Input,
                },
            ],
            windows: vec![
                WindowSpec {
                    buffer: "messages".into(),
                    opts: WinOpts {
                        split: Split::Top,
                        size: Size::Fill,
                        ..WinOpts::default()
                    },
                },
                WindowSpec {
                    buffer: "input".into(),
                    opts: WinOpts {
                        split: Split::Bottom,
                        size: Size::Fixed(3),
                        border: Border::Plain,
                        ..WinOpts::default()
                    },
                },
            ],
            opts: GlobalOpts::default(),
        }
    }
}

impl UiModel {
    pub fn buffer_kind(&self, name: &str) -> Option<BufferKind> {
        self.buffers.iter().find(|b| b.name == name).map(|b| b.kind)
    }
}

fn is_vertical(split: Split) -> bool {
    matches!(split, Split::Top | Split::Bottom)
}

pub fn layout(area: Rect, windows: &[WindowSpec]) -> Vec<Rect> {
    let mut rects = Vec::with_capacity(windows.len());
    let mut remaining_area = area;

    for (index, win) in windows.iter().enumerate() {
        let vertical = is_vertical(win.opts.split);
        let later = &windows[index + 1..];

        let reserved: u16 = later
            .iter()
            .filter(|w| is_vertical(w.opts.split) == vertical)
            .filter_map(|w| match w.opts.size {
                Size::Fixed(n) => Some(n),
                Size::Fill => None,
            })
            .sum();
        let later_fills = later
            .iter()
            .filter(|w| is_vertical(w.opts.split) == vertical && w.opts.size == Size::Fill)
            .count();
        let fills = u16::try_from(later_fills)
            .unwrap_or(u16::MAX)
            .saturating_add(1);

        let avail = if vertical {
            remaining_area.height
        } else {
            remaining_area.width
        };
        let take = match win.opts.size {
            Size::Fill => avail.saturating_sub(reserved) / fills.max(1),
            Size::Fixed(n) => n.min(avail),
        };

        let (window_area, rest) = carve(remaining_area, win.opts.split, take);
        rects.push(window_area);
        remaining_area = rest;
    }
    rects
}

fn carve(area: Rect, split: Split, take: u16) -> (Rect, Rect) {
    match split {
        Split::Top => {
            let window_area = Rect {
                height: take,
                ..area
            };
            let rest = Rect {
                y: area.y + take,
                height: area.height.saturating_sub(take),
                ..area
            };
            (window_area, rest)
        }
        Split::Bottom => {
            let window_area = Rect {
                y: area.y + area.height.saturating_sub(take),
                height: take,
                ..area
            };
            let rest = Rect {
                height: area.height.saturating_sub(take),
                ..area
            };
            (window_area, rest)
        }
        Split::Left => {
            let window_area = Rect {
                width: take,
                ..area
            };
            let rest = Rect {
                x: area.x + take,
                width: area.width.saturating_sub(take),
                ..area
            };
            (window_area, rest)
        }
        Split::Right => {
            let window_area = Rect {
                x: area.x + area.width.saturating_sub(take),
                width: take,
                ..area
            };
            let rest = Rect {
                width: area.width.saturating_sub(take),
                ..area
            };
            (window_area, rest)
        }
    }
}
