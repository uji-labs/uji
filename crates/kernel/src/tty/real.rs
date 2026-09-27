use std::io::{self, Stdout, Write};
use std::sync::Arc;
use std::sync::Once;
use std::sync::atomic::{AtomicBool, Ordering};

use crossterm::cursor::SetCursorStyle;
use crossterm::event::{
    DisableBracketedPaste, EnableBracketedPaste, KeyboardEnhancementFlags,
    PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
};
use crossterm::terminal::{
    EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode,
    supports_keyboard_enhancement,
};
use crossterm::{execute, queue};
use ratatui::Terminal;
use ratatui::backend::{Backend, CrosstermBackend};
use ratatui::buffer::Buffer;
use ratatui::layout::Position;
use tokio::sync::mpsc;

use super::input::{Input, Reader};
use super::screen::{Cursor, Screen, Shape, Surface};

const ENABLE_MOUSE: &str = "\x1b[?1000h\x1b[?1002h\x1b[?1006h";
const DISABLE_MOUSE: &str = "\x1b[?1006l\x1b[?1002l\x1b[?1000l";
const ENHANCEMENTS: KeyboardEnhancementFlags = KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES
    .union(KeyboardEnhancementFlags::REPORT_ALTERNATE_KEYS);

static ACTIVE: AtomicBool = AtomicBool::new(false);
static ENHANCED: AtomicBool = AtomicBool::new(false);
static GUARDED: Once = Once::new();

fn enter(out: &mut impl Write) -> io::Result<()> {
    enable_raw_mode()?;
    execute!(out, EnterAlternateScreen)?;
    write!(out, "{ENABLE_MOUSE}")?;
    execute!(out, EnableBracketedPaste)?;
    if supports_keyboard_enhancement().unwrap_or(false) {
        execute!(out, PushKeyboardEnhancementFlags(ENHANCEMENTS))?;
        ENHANCED.store(true, Ordering::Relaxed);
    }
    out.flush()?;
    ACTIVE.store(true, Ordering::Relaxed);
    Ok(())
}

fn leave(out: &mut impl Write) -> io::Result<()> {
    ACTIVE.store(false, Ordering::Relaxed);
    disable_raw_mode()?;
    if ENHANCED.swap(false, Ordering::Relaxed) {
        execute!(out, PopKeyboardEnhancementFlags)?;
    }
    write!(out, "{DISABLE_MOUSE}")?;
    execute!(
        out,
        DisableBracketedPaste,
        LeaveAlternateScreen,
        crossterm::cursor::Show
    )?;
    out.flush()
}

pub(crate) fn restore() {
    if ACTIVE.load(Ordering::Relaxed) {
        drop(leave(&mut io::stdout()));
    }
}

fn guard_against_panic() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        restore();
        previous(info);
    }));
}

struct Real {
    terminal: Terminal<CrosstermBackend<Stdout>>,
    paused: Arc<AtomicBool>,
}

fn cursor_style(shape: Shape) -> SetCursorStyle {
    match shape {
        Shape::Block => SetCursorStyle::SteadyBlock,
        Shape::Bar => SetCursorStyle::SteadyBar,
        Shape::Underline => SetCursorStyle::SteadyUnderScore,
    }
}

impl Surface for Real {
    fn buffer(&mut self) -> &mut Buffer {
        self.terminal.current_buffer_mut()
    }

    fn size(&mut self) -> mlua::Result<(u16, u16)> {
        self.terminal.autoresize().map_err(mlua::Error::external)?;
        let area = self.terminal.current_buffer_mut().area;
        Ok((area.width, area.height))
    }

    fn present(&mut self, cursor: Option<Cursor>) -> mlua::Result<()> {
        self.terminal.flush().map_err(mlua::Error::external)?;
        match cursor {
            Some(cursor) => {
                queue!(self.terminal.backend_mut(), cursor_style(cursor.shape))
                    .map_err(mlua::Error::external)?;
                self.terminal
                    .set_cursor_position(Position::new(cursor.col, cursor.row))
                    .map_err(mlua::Error::external)?;
                self.terminal.show_cursor().map_err(mlua::Error::external)?;
            }
            None => self.terminal.hide_cursor().map_err(mlua::Error::external)?,
        }
        self.terminal.swap_buffers();
        Backend::flush(self.terminal.backend_mut()).map_err(mlua::Error::external)
    }

    fn write(&mut self, bytes: &[u8]) -> mlua::Result<()> {
        let backend = self.terminal.backend_mut();
        backend.write_all(bytes).map_err(mlua::Error::external)?;
        Write::flush(backend).map_err(mlua::Error::external)
    }

    fn suspend(&mut self) -> mlua::Result<()> {
        self.paused.store(true, Ordering::Relaxed);
        Reader::settle();
        leave(self.terminal.backend_mut()).map_err(mlua::Error::external)
    }

    fn resume(&mut self) -> mlua::Result<()> {
        enter(self.terminal.backend_mut()).map_err(mlua::Error::external)?;
        self.terminal.clear().map_err(mlua::Error::external)?;
        self.paused.store(false, Ordering::Relaxed);
        Ok(())
    }

    fn close(&mut self) -> mlua::Result<()> {
        self.paused.store(true, Ordering::Relaxed);
        if ACTIVE.load(Ordering::Relaxed) {
            leave(self.terminal.backend_mut()).map_err(mlua::Error::external)?;
        }
        Ok(())
    }
}

impl Drop for Real {
    fn drop(&mut self) {
        restore();
    }
}

pub(crate) fn open() -> mlua::Result<(Screen, Input)> {
    GUARDED.call_once(guard_against_panic);
    let mut stdout = io::stdout();
    enter(&mut stdout).map_err(mlua::Error::external)?;
    let terminal = Terminal::new(CrosstermBackend::new(stdout)).map_err(mlua::Error::external)?;
    let paused = Arc::new(AtomicBool::new(false));
    let (sender, events) = mpsc::unbounded_channel();
    let reader = Reader::spawn(sender, Arc::clone(&paused));
    Ok((
        Screen::new(Box::new(Real { terminal, paused })),
        Input::new(events, Some(reader)),
    ))
}
