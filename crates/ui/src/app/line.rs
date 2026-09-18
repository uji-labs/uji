//! One editable line of text with a cursor: the editing core every typed
//! surface shares.
//!
//! The composer, the prompt's value and a picker's query all edit text the same
//! way, so they all hold one of these and the readline actions are written once.
//! Offsets are byte offsets kept on character boundaries; `revision` ticks on
//! every change so callers can tell an edit from a bare cursor move.

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Line {
    text: String,
    cursor: usize,
    kill: String,
    revision: u64,
}

impl Line {
    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn cursor(&self) -> usize {
        self.cursor
    }

    /// Bumped by every change to the text, never by a cursor move.
    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn is_empty(&self) -> bool {
        self.text.is_empty()
    }

    fn touch(&mut self) {
        self.revision = self.revision.wrapping_add(1);
    }

    pub fn set(&mut self, text: String) {
        self.text = text;
        self.cursor = self.text.len();
        self.touch();
    }

    pub fn clear(&mut self) {
        self.text.clear();
        self.cursor = 0;
        self.touch();
    }

    pub fn take(&mut self) -> String {
        self.cursor = 0;
        self.touch();
        std::mem::take(&mut self.text)
    }

    pub fn insert(&mut self, c: char) {
        self.text.insert(self.cursor, c);
        self.cursor = self.cursor.saturating_add(c.len_utf8());
        self.touch();
    }

    pub fn insert_str(&mut self, text: &str) {
        self.text.insert_str(self.cursor, text);
        self.cursor = self.cursor.saturating_add(text.len());
        self.touch();
    }

    pub fn backspace(&mut self) {
        if self.cursor == 0 {
            return;
        }
        let from = prev_boundary(&self.text, self.cursor);
        self.text.replace_range(from..self.cursor, "");
        self.cursor = from;
        self.touch();
    }

    /// Remove the `bytes` of text just before the cursor, rounded out to a
    /// character boundary.
    pub fn delete_before(&mut self, bytes: usize) {
        let mut from = self.cursor.saturating_sub(bytes);
        while from > 0 && !self.text.is_char_boundary(from) {
            from = from.saturating_sub(1);
        }
        self.text.replace_range(from..self.cursor, "");
        self.cursor = from;
        self.touch();
    }

    pub fn delete_forward(&mut self) {
        if self.cursor >= self.text.len() {
            return;
        }
        let to = next_boundary(&self.text, self.cursor);
        self.text.replace_range(self.cursor..to, "");
        self.touch();
    }

    pub fn left(&mut self) {
        self.cursor = prev_boundary(&self.text, self.cursor);
    }

    pub fn right(&mut self) {
        self.cursor = next_boundary(&self.text, self.cursor);
    }

    /// Start of the line the cursor is on, not of the whole text: on a multi-line
    /// composer `<C-a>` behaves the way it does in a shell.
    pub fn home(&mut self) {
        self.cursor = self.line_start(self.cursor);
    }

    pub fn end(&mut self) {
        self.cursor = self.line_end(self.cursor);
    }

    pub fn word_left(&mut self) {
        self.cursor = self.word_start_before(self.cursor);
    }

    pub fn word_right(&mut self) {
        self.cursor = self.word_end_after(self.cursor);
    }

    /// `<C-w>`: back over whitespace, then over everything up to the next
    /// whitespace — readline's `unix-word-rubout`, which is what makes it useful
    /// for deleting a path or a flag in one go.
    pub fn delete_word_back(&mut self) {
        let mut at = self.cursor;
        while let Some(c) = char_before(&self.text, at).filter(|c| c.is_whitespace()) {
            at = at.saturating_sub(c.len_utf8());
        }
        while let Some(c) = char_before(&self.text, at).filter(|c| !c.is_whitespace()) {
            at = at.saturating_sub(c.len_utf8());
        }
        self.kill_range(at, self.cursor);
        self.cursor = at;
    }

    pub fn delete_word_forward(&mut self) {
        let to = self.word_end_after(self.cursor);
        self.kill_range(self.cursor, to);
    }

    pub fn delete_to_start(&mut self) {
        let from = self.line_start(self.cursor);
        self.kill_range(from, self.cursor);
        self.cursor = from;
    }

    pub fn delete_to_end(&mut self) {
        let to = self.line_end(self.cursor);
        self.kill_range(self.cursor, to);
    }

    /// Put back whatever the last kill took.
    pub fn yank(&mut self) {
        if self.kill.is_empty() {
            return;
        }
        let killed = std::mem::take(&mut self.kill);
        self.insert_str(&killed);
        self.kill = killed;
    }

    /// Swap the two characters around the cursor, or the last two when the
    /// cursor sits at the end of the line.
    pub fn transpose(&mut self) {
        let at_end =
            self.cursor >= self.text.len() || char_at(&self.text, self.cursor) == Some('\n');
        let right = if at_end {
            self.cursor
        } else {
            next_boundary(&self.text, self.cursor)
        };
        let mid = if at_end {
            prev_boundary(&self.text, right)
        } else {
            self.cursor
        };
        let left = prev_boundary(&self.text, mid);
        if left == mid || mid == right {
            return;
        }
        let swapped = format!("{}{}", &self.text[mid..right], &self.text[left..mid]);
        self.text.replace_range(left..right, &swapped);
        self.cursor = right;
        self.touch();
    }

    /// Move a line up, keeping the column. False when already on the first line,
    /// so the caller can fall back to history.
    pub fn up(&mut self) -> bool {
        let start = self.line_start(self.cursor);
        if start == 0 {
            return false;
        }
        let column = self.text[start..self.cursor].chars().count();
        let above = start.saturating_sub(1);
        self.cursor = self.column_offset(self.line_start(above), above, column);
        true
    }

    pub fn down(&mut self) -> bool {
        let end = self.line_end(self.cursor);
        if end >= self.text.len() {
            return false;
        }
        let start = self.line_start(self.cursor);
        let column = self.text[start..self.cursor].chars().count();
        let below = end.saturating_add(1);
        self.cursor = self.column_offset(below, self.line_end(below), column);
        true
    }

    fn kill_range(&mut self, from: usize, to: usize) {
        if from >= to {
            return;
        }
        self.kill = self.text[from..to].to_string();
        self.text.replace_range(from..to, "");
        self.touch();
    }

    fn line_start(&self, at: usize) -> usize {
        self.text[..at]
            .rfind('\n')
            .map_or(0, |found| found.saturating_add(1))
    }

    fn line_end(&self, at: usize) -> usize {
        self.text[at..]
            .find('\n')
            .map_or(self.text.len(), |found| at.saturating_add(found))
    }

    fn column_offset(&self, start: usize, end: usize, column: usize) -> usize {
        self.text[start..end]
            .char_indices()
            .nth(column)
            .map_or(end, |(at, _)| start.saturating_add(at))
    }

    fn word_start_before(&self, at: usize) -> usize {
        let mut at = at;
        while let Some(c) = char_before(&self.text, at).filter(|c| !is_word(*c)) {
            at = at.saturating_sub(c.len_utf8());
        }
        while let Some(c) = char_before(&self.text, at).filter(|c| is_word(*c)) {
            at = at.saturating_sub(c.len_utf8());
        }
        at
    }

    fn word_end_after(&self, at: usize) -> usize {
        let mut at = at;
        while let Some(c) = char_at(&self.text, at).filter(|c| !is_word(*c)) {
            at = at.saturating_add(c.len_utf8());
        }
        while let Some(c) = char_at(&self.text, at).filter(|c| is_word(*c)) {
            at = at.saturating_add(c.len_utf8());
        }
        at
    }
}

fn is_word(c: char) -> bool {
    c.is_alphanumeric() || c == '_'
}

fn char_before(text: &str, at: usize) -> Option<char> {
    text.get(..at).and_then(|before| before.chars().next_back())
}

fn char_at(text: &str, at: usize) -> Option<char> {
    text.get(at..).and_then(|after| after.chars().next())
}

pub(crate) fn prev_boundary(text: &str, index: usize) -> usize {
    char_before(text, index).map_or(0, |c| index.saturating_sub(c.len_utf8()))
}

pub(crate) fn next_boundary(text: &str, index: usize) -> usize {
    char_at(text, index).map_or(text.len(), |c| index.saturating_add(c.len_utf8()))
}

#[cfg(test)]
mod tests {
    use super::Line;

    fn at(text: &str, cursor: usize) -> Line {
        let mut line = Line::default();
        line.set(text.to_string());
        line.cursor = cursor;
        line
    }

    #[test]
    fn delete_word_back_takes_whitespace_and_word() {
        let mut line = at("cargo run --release", 19);
        line.delete_word_back();
        assert_eq!(line.text(), "cargo run ");
        assert_eq!(line.cursor(), 10);
        line.delete_word_back();
        assert_eq!(line.text(), "cargo ");
    }

    #[test]
    fn delete_word_back_keeps_the_path_together() {
        let mut line = at("open crates/ui/src", 18);
        line.delete_word_back();
        assert_eq!(line.text(), "open ");
    }

    #[test]
    fn word_motions_step_over_punctuation() {
        let mut line = at("one two_three four", 0);
        line.word_right();
        assert_eq!(line.cursor(), 3);
        line.word_right();
        assert_eq!(line.cursor(), 13);
        line.word_left();
        assert_eq!(line.cursor(), 4);
    }

    #[test]
    fn delete_forward_takes_the_character_under_the_cursor() {
        let mut line = at("abc", 1);
        line.delete_forward();
        assert_eq!(line.text(), "ac");
        assert_eq!(line.cursor(), 1);
        line.end();
        line.delete_forward();
        assert_eq!(line.text(), "ac", "nothing to delete at the end");
    }

    #[test]
    fn delete_word_forward_leaves_the_cursor_put() {
        let mut line = at("cargo run --release", 6);
        line.delete_word_forward();
        assert_eq!(line.text(), "cargo  --release");
        assert_eq!(line.cursor(), 6);
    }

    #[test]
    fn right_walks_forward_and_stops_at_the_end() {
        let mut line = at("ab", 0);
        line.right();
        assert_eq!(line.cursor(), 1);
        line.right();
        line.right();
        assert_eq!(line.cursor(), 2);
    }

    #[test]
    fn clear_empties_the_line_and_the_cursor() {
        let mut line = at("something typed", 5);
        line.clear();
        assert!(line.is_empty());
        assert_eq!(line.cursor(), 0);
    }

    #[test]
    fn delete_before_rounds_out_to_a_character() {
        let mut line = at("héllo", "héllo".len());
        line.delete_before(2);
        assert_eq!(line.text(), "hél");
    }

    #[test]
    fn kill_and_yank_round_trip() {
        let mut line = at("hello world", 5);
        line.delete_to_start();
        assert_eq!(line.text(), " world");
        line.end();
        line.yank();
        assert_eq!(line.text(), " worldhello");
    }

    #[test]
    fn delete_to_end_stops_at_the_newline() {
        let mut line = at("first\nsecond", 2);
        line.delete_to_end();
        assert_eq!(line.text(), "fi\nsecond");
    }

    #[test]
    fn home_and_end_stay_on_the_current_line() {
        let mut line = at("first\nsecond", 8);
        line.home();
        assert_eq!(line.cursor(), 6);
        line.end();
        assert_eq!(line.cursor(), 12);
    }

    #[test]
    fn up_and_down_keep_the_column() {
        // "abcd\nefgh": offset 7 is column 2 of the second line.
        let mut line = at("abcd\nefgh", 7);
        assert!(line.up());
        assert_eq!(line.cursor(), 2);
        assert!(line.down());
        assert_eq!(line.cursor(), 7);
    }

    #[test]
    fn up_reports_false_on_the_first_line() {
        let mut line = at("only one line", 4);
        assert!(!line.up());
        assert!(!line.down());
    }

    #[test]
    fn up_clamps_to_a_shorter_line() {
        let mut line = at("ab\nlonger", 9);
        assert!(line.up());
        assert_eq!(line.cursor(), 2);
    }

    #[test]
    fn transpose_swaps_around_the_cursor() {
        let mut line = at("ab", 2);
        line.transpose();
        assert_eq!(line.text(), "ba");
        assert_eq!(line.cursor(), 2);
        let mut line = at("abc", 1);
        line.transpose();
        assert_eq!(line.text(), "bac");
        assert_eq!(line.cursor(), 2);
    }

    #[test]
    fn multibyte_edits_stay_on_boundaries() {
        let mut line = at("héllo wörld", "héllo wörld".len());
        line.delete_word_back();
        assert_eq!(line.text(), "héllo ");
        line.backspace();
        assert_eq!(line.text(), "héllo");
        line.left();
        line.left();
        line.left();
        line.backspace();
        assert_eq!(line.text(), "hllo");
    }

    #[test]
    fn a_cursor_move_leaves_the_revision_alone() {
        let mut line = at("text", 0);
        let revision = line.revision();
        line.right();
        line.word_right();
        line.end();
        assert_eq!(line.revision(), revision);
        line.insert('!');
        assert_ne!(line.revision(), revision);
    }
}
