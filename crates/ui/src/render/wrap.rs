pub(crate) fn text(source: &str, width: usize) -> Vec<String> {
    if width == 0 {
        return source.lines().map(str::to_string).collect();
    }
    let mut out = Vec::new();
    for line in source.lines() {
        wrap_line(line, width, &mut out);
    }
    out
}

fn wrap_line(line: &str, width: usize, out: &mut Vec<String>) {
    if line.chars().count() <= width {
        out.push(line.to_string());
        return;
    }
    let mut row = Row::new(width);
    for word in line.split_whitespace() {
        if word.chars().count() > width {
            row.flush(out);
            for letter in word.chars() {
                row.letter(letter, out);
            }
        } else {
            row.word(word, out);
        }
    }
    row.flush(out);
}

struct Row {
    width: usize,
    text: String,
}

impl Row {
    fn new(width: usize) -> Self {
        Self {
            width,
            text: String::new(),
        }
    }

    fn len(&self) -> usize {
        self.text.chars().count()
    }

    fn flush(&mut self, out: &mut Vec<String>) {
        if !self.text.is_empty() {
            out.push(std::mem::take(&mut self.text));
        }
    }

    fn word(&mut self, word: &str, out: &mut Vec<String>) {
        if self.len() + 1 + word.chars().count() > self.width {
            self.flush(out);
        } else if !self.text.is_empty() {
            self.text.push(' ');
        }
        self.text.push_str(word);
    }

    fn letter(&mut self, letter: char, out: &mut Vec<String>) {
        if self.len() == self.width {
            self.flush(out);
        }
        self.text.push(letter);
    }
}

/// Split typed characters into the rows they occupy.
///
/// A newline ends its row and belongs to it, so a row range still covers every
/// character and a cursor sitting on a newline has a row to be drawn on. Rows
/// are ranges rather than strings because the caller needs to know which row the
/// cursor offset falls in.
pub(crate) fn ranges(chars: &[char], width: usize) -> Vec<(usize, usize)> {
    if width == 0 || chars.is_empty() {
        return vec![(0, chars.len())];
    }
    let mut rows = Vec::new();
    let mut start = 0;
    for at in 0..chars.len() {
        if chars[at] == '\n' {
            fold(chars, start, at.saturating_add(1), width, &mut rows);
            start = at.saturating_add(1);
        }
    }
    if start < chars.len() || ends_line(chars) {
        fold(chars, start, chars.len(), width, &mut rows);
    }
    rows
}

fn ends_line(chars: &[char]) -> bool {
    chars.last() == Some(&'\n')
}

/// Wrap one logical line, keeping any trailing newline on the last row it makes.
fn fold(chars: &[char], start: usize, end: usize, width: usize, rows: &mut Vec<(usize, usize)>) {
    let newline = end > start && chars[end.saturating_sub(1)] == '\n';
    let content = if newline { end.saturating_sub(1) } else { end };
    let mut at = start;
    while at < content {
        let hard_end = at.saturating_add(width).min(content);
        if hard_end == content {
            rows.push((at, content));
            at = content;
            break;
        }
        let stop = (at..hard_end)
            .rev()
            .find(|index| chars[*index] == ' ')
            .map_or(hard_end, |index| index.saturating_add(1));
        rows.push((at, stop));
        at = stop;
    }
    if at == start && content == start {
        rows.push((start, start));
    }
    if newline && let Some(last) = rows.last_mut() {
        last.1 = end;
    }
}

#[cfg(test)]
mod tests {
    use super::ranges;

    fn rows(text: &str, width: usize) -> Vec<String> {
        let chars: Vec<char> = text.chars().collect();
        ranges(&chars, width)
            .into_iter()
            .map(|(start, end)| chars[start..end].iter().collect())
            .collect()
    }

    #[test]
    fn a_newline_starts_a_row() {
        assert_eq!(rows("ab\ncd", 20), vec!["ab\n", "cd"]);
    }

    #[test]
    fn a_trailing_newline_leaves_an_empty_row_to_type_on() {
        assert_eq!(rows("ab\n", 20), vec!["ab\n", ""]);
    }

    #[test]
    fn a_blank_line_keeps_its_row() {
        assert_eq!(rows("a\n\nb", 20), vec!["a\n", "\n", "b"]);
    }

    #[test]
    fn long_lines_still_wrap_on_a_space() {
        assert_eq!(rows("aaa bbb ccc", 5), vec!["aaa ", "bbb ", "ccc"]);
    }

    #[test]
    fn every_character_belongs_to_exactly_one_row() {
        let text = "hello there\nsecond line that is rather long\n\nend";
        let chars: Vec<char> = text.chars().collect();
        let mut covered = 0;
        for (start, end) in ranges(&chars, 12) {
            assert_eq!(start, covered, "rows must not skip or overlap");
            covered = end;
        }
        assert_eq!(covered, chars.len());
    }
}
