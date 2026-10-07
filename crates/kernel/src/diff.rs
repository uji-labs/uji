use similar::{ChangeTag, InlineChange, TextDiff};
use uji_macros::{function, value};

#[value]
#[serde(rename_all = "lowercase")]
enum Kind {
    Context,
    Removed,
    Added,
}

#[value]
struct Part {
    text: String,
    changed: bool,
}

#[value]
struct Line {
    kind: Kind,
    old: Option<usize>,
    new: Option<usize>,
    parts: Vec<Part>,
}

fn line(change: &InlineChange<'_, str>) -> Line {
    let kind = match change.tag() {
        ChangeTag::Equal => Kind::Context,
        ChangeTag::Delete => Kind::Removed,
        ChangeTag::Insert => Kind::Added,
    };
    let parts = change
        .iter_strings_lossy()
        .map(|(changed, text)| Part {
            text: text.trim_end_matches(['\r', '\n']).to_string(),
            changed,
        })
        .filter(|part| !part.text.is_empty())
        .collect();
    Line {
        kind,
        old: change.old_index().map(|at| at.saturating_add(1)),
        new: change.new_index().map(|at| at.saturating_add(1)),
        parts,
    }
}

#[function]
fn diff(old: &str, new: &str, context: usize) -> Vec<Vec<Line>> {
    let diff = TextDiff::from_lines(old, new);
    diff.grouped_ops(context)
        .iter()
        .map(|group| {
            group
                .iter()
                .flat_map(|op| diff.iter_inline_changes(op))
                .map(|change| line(&change))
                .collect()
        })
        .collect()
}
