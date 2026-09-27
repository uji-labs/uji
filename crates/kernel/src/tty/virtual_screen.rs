use ratatui::Terminal;
use ratatui::backend::TestBackend;
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use tokio::sync::watch;

use super::VirtualTerminal;
use super::input::Input;
use super::screen::{Cursor, Screen, Surface};

struct Virtual {
    terminal: Terminal<TestBackend>,
    frames: watch::Sender<Vec<String>>,
    size: watch::Receiver<(u16, u16)>,
}

impl Virtual {
    fn snapshot(&self) -> Vec<String> {
        let buffer = self.terminal.backend().buffer();
        let area = buffer.area;
        (area.top()..area.bottom())
            .map(|row| {
                (area.left()..area.right())
                    .map(|col| buffer[(col, row)].symbol())
                    .collect()
            })
            .collect()
    }
}

impl Surface for Virtual {
    fn buffer(&mut self) -> &mut Buffer {
        self.terminal.current_buffer_mut()
    }

    fn size(&mut self) -> mlua::Result<(u16, u16)> {
        let (width, height) = *self.size.borrow_and_update();
        let area = self.terminal.current_buffer_mut().area;
        if (area.width, area.height) != (width, height) {
            self.terminal.backend_mut().resize(width, height);
            self.terminal
                .resize(Rect::new(0, 0, width, height))
                .map_err(mlua::Error::external)?;
        }
        Ok((width, height))
    }

    fn present(&mut self, _cursor: Option<Cursor>) -> mlua::Result<()> {
        self.terminal.flush().map_err(mlua::Error::external)?;
        self.terminal.swap_buffers();
        self.frames.send_replace(self.snapshot());
        Ok(())
    }

    fn write(&mut self, _bytes: &[u8]) -> mlua::Result<()> {
        Ok(())
    }

    fn suspend(&mut self) -> mlua::Result<()> {
        Ok(())
    }

    fn resume(&mut self) -> mlua::Result<()> {
        Ok(())
    }

    fn close(&mut self) -> mlua::Result<()> {
        Ok(())
    }
}

pub(crate) fn open(terminal: VirtualTerminal) -> mlua::Result<(Screen, Input)> {
    let (width, height) = *terminal.size.borrow();
    let surface = Terminal::new(TestBackend::new(width, height)).map_err(mlua::Error::external)?;
    Ok((
        Screen::new(Box::new(Virtual {
            terminal: surface,
            frames: terminal.frames,
            size: terminal.size,
        })),
        Input::new(terminal.events, None),
    ))
}
