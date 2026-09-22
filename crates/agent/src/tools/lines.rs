use std::io::BufRead;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Line {
    Read { truncated: bool },
    Eof,
}

pub fn read<R: BufRead>(reader: &mut R, line: &mut String, max: usize) -> std::io::Result<Line> {
    line.clear();
    let mut started = false;
    let mut truncated = false;
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok(if started {
                Line::Read { truncated }
            } else {
                Line::Eof
            });
        }
        started = true;
        let ended = available.iter().position(|byte| *byte == b'\n');
        let chunk = ended.map_or(available, |at| &available[..at]);
        let room = max.saturating_sub(line.len());
        let take = chunk.len().min(room);
        let kept = String::from_utf8_lossy(&chunk[..take]).into_owned();
        let consumed = chunk.len().saturating_add(usize::from(ended.is_some()));
        truncated |= take < chunk.len();
        line.push_str(&kept);
        reader.consume(consumed);
        if ended.is_some() {
            return Ok(Line::Read { truncated });
        }
    }
}
