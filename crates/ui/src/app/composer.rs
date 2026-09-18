use super::line::Line;

#[derive(Debug, Default)]
pub struct Composer {
    line: Line,
    recall: Recall,
    pastes: crate::app::paste::Pastes,
}

#[derive(Debug, Default)]
enum Recall {
    #[default]
    Editing,
    Browsing {
        at: usize,
        draft: String,
    },
}

impl Composer {
    pub fn text(&self) -> &str {
        self.line.text()
    }

    pub fn cursor(&self) -> usize {
        self.line.cursor()
    }

    pub fn revision(&self) -> u64 {
        self.line.revision()
    }

    pub fn line(&self) -> &Line {
        &self.line
    }

    /// Run one edit against the composed line.
    ///
    /// Editing leaves history recall, and any paste marker the edit removed part
    /// of stops standing for its text, so a half-deleted marker cannot expand on
    /// submit.
    pub fn edit(&mut self, change: impl FnOnce(&mut Line)) {
        self.recall = Recall::Editing;
        change(&mut self.line);
        self.pastes.prune(self.line.text());
    }

    pub fn paste(&mut self, text: &str) {
        let cleaned = crate::app::paste::clean(text);
        if cleaned.is_empty() {
            return;
        }
        let inserted = self.pastes.stash(&cleaned);
        self.edit(move |line| line.insert_str(&inserted));
    }

    /// Backspace, except that it swallows a whole paste marker at once: the
    /// marker stands for text the user never typed, so rubbing out its last
    /// bracket alone would leave a stub that expands into nothing.
    pub fn backspace(&mut self) {
        if self.drop_marker() {
            return;
        }
        self.edit(Line::backspace);
    }

    fn drop_marker(&mut self) -> bool {
        let cursor = self.line.cursor();
        let Some((id, width)) = self
            .line
            .text()
            .get(..cursor)
            .and_then(|before| self.pastes.marker_ending_at(before))
        else {
            return false;
        };
        self.pastes.forget(id);
        self.edit(move |line| line.delete_before(width));
        true
    }

    pub fn clear(&mut self) {
        self.pastes.clear();
        self.edit(Line::clear);
    }

    pub fn set(&mut self, next: String) {
        self.edit(move |line| line.set(next));
    }

    pub fn take(&mut self) -> String {
        self.recall = Recall::Editing;
        let taken = self.line.take();
        let expanded = self.pastes.expand(&taken);
        self.pastes.clear();
        expanded
    }

    /// A trailing backslash means "keep typing": swap it for a newline instead
    /// of sending. It is the only way to compose a multi-line message on a
    /// terminal that cannot report shift+enter.
    pub fn continue_line(&mut self) -> bool {
        if !self.line.text().ends_with('\\') || self.line.cursor() != self.line.text().len() {
            return false;
        }
        self.edit(|line| {
            line.backspace();
            line.insert('\n');
        });
        true
    }

    /// Move a line within the draft, if there is one to move to. Browsing
    /// history is left alone: walking a recalled message is not editing it.
    pub fn up(&mut self) -> bool {
        self.line.up()
    }

    pub fn down(&mut self) -> bool {
        self.line.down()
    }

    pub fn recall_prev(&mut self, lookup: impl Fn(usize) -> Option<String>) -> bool {
        let at = match &self.recall {
            Recall::Editing => 0,
            Recall::Browsing { at, .. } => at.saturating_add(1),
        };
        let Some(text) = lookup(at) else {
            return false;
        };
        if let Recall::Browsing { at: browsing, .. } = &mut self.recall {
            *browsing = at;
        } else {
            let draft = self.line.take();
            self.recall = Recall::Browsing { at, draft };
        }
        self.line.set(text);
        true
    }

    pub fn recall_next(&mut self, lookup: impl Fn(usize) -> Option<String>) -> bool {
        let Recall::Browsing { at, .. } = &self.recall else {
            return false;
        };
        let at = *at;
        let Some(newer) = at.checked_sub(1) else {
            let Recall::Browsing { draft, .. } = std::mem::take(&mut self.recall) else {
                return false;
            };
            self.line.set(draft);
            return true;
        };
        let Some(text) = lookup(newer) else {
            return false;
        };
        if let Recall::Browsing { at, .. } = &mut self.recall {
            *at = newer;
        }
        self.line.set(text);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::Composer;
    use crate::app::line::Line;

    fn pasted(lines: usize) -> String {
        (0..lines)
            .map(|at| format!("line {at}"))
            .collect::<Vec<_>>()
            .join("\n")
    }

    #[test]
    fn a_marker_expands_on_submit() {
        let mut composer = Composer::default();
        composer.paste(&pasted(5));
        assert!(composer.text().starts_with("[paste #1"));
        assert_eq!(composer.take(), pasted(5));
    }

    #[test]
    fn backspace_drops_the_whole_marker() {
        let mut composer = Composer::default();
        composer.paste(&pasted(5));
        composer.backspace();
        assert_eq!(composer.text(), "");
    }

    /// A kill that eats part of a marker must not leave the rest expanding.
    #[test]
    fn a_kill_across_a_marker_forgets_it() {
        let mut composer = Composer::default();
        composer.edit(|line| line.insert('x'));
        composer.paste(&pasted(5));
        composer.edit(Line::delete_word_back);
        let taken = composer.take();
        assert!(!taken.contains("line 0"), "expanded a half-deleted marker");
    }

    #[test]
    fn a_trailing_backslash_becomes_a_newline() {
        let mut composer = Composer::default();
        composer.set(String::from("first \\"));
        assert!(composer.continue_line());
        assert_eq!(composer.text(), "first \n");
        assert!(!composer.continue_line());
    }

    #[test]
    fn recall_browses_and_comes_back_to_the_draft() {
        let mut composer = Composer::default();
        composer.set(String::from("draft"));
        let history = |back: usize| {
            ["newest", "older"]
                .get(back)
                .map(|text| (*text).to_string())
        };
        assert!(composer.recall_prev(history));
        assert_eq!(composer.text(), "newest");
        assert!(composer.recall_prev(history));
        assert_eq!(composer.text(), "older");
        assert!(composer.recall_next(history));
        assert!(composer.recall_next(history));
        assert_eq!(composer.text(), "draft");
    }
}
