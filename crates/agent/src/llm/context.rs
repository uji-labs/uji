use std::collections::HashSet;

use crate::session::model::{Message, StoredMessage};

const SUMMARY_HEADER: &str = "Summary of the earlier part of this conversation:";
const FILES_HEADER: &str = "Files touched so far:";
const PATH_TOOLS: &[&str] = &["read_file", "edit_file", "write_file"];

pub fn files_touched(messages: &[&Message]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for message in messages {
        let Message::Assistant { tool_calls, .. } = message else {
            continue;
        };
        for call in tool_calls {
            if !PATH_TOOLS.contains(&call.name.as_str()) {
                continue;
            }
            let Ok(args) = serde_json::from_str::<serde_json::Value>(&call.arguments) else {
                continue;
            };
            let Some(path) = args.get("path").and_then(serde_json::Value::as_str) else {
                continue;
            };
            if !out.iter().any(|seen| seen == path) {
                out.push(path.to_string());
            }
        }
    }
    out
}

pub fn merge_files(into: &mut Vec<String>, extra: &[String]) {
    let mut known: HashSet<String> = into.iter().cloned().collect();
    let fresh: Vec<String> = extra
        .iter()
        .filter(|path| known.insert((*path).clone()))
        .cloned()
        .collect();
    into.extend(fresh);
}

pub fn previous_summary(message: &Message) -> Option<&str> {
    let Message::User { text } = message else {
        return None;
    };
    let body = text.strip_prefix(SUMMARY_HEADER)?;
    Some(
        body.rsplit_once(FILES_HEADER)
            .map_or(body, |(head, _)| head)
            .trim(),
    )
}

pub fn previous_files(message: &Message) -> Vec<String> {
    let Message::User { text } = message else {
        return Vec::new();
    };
    let Some((_, listed)) = text.rsplit_once(FILES_HEADER) else {
        return Vec::new();
    };
    listed
        .lines()
        .next()
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|path| !path.is_empty())
        .map(str::to_string)
        .collect()
}

pub fn summary_message(summary: &str, files: &[String]) -> Message {
    let mut text = format!("{SUMMARY_HEADER}\n\n{summary}");
    if !files.is_empty() {
        text.push_str("\n\n");
        text.push_str(FILES_HEADER);
        text.push(' ');
        text.push_str(&files.join(", "));
    }
    Message::User { text }
}

pub fn build(stored: &[StoredMessage]) -> Vec<Message> {
    let (checkpoint, rest) = split_at_compaction(stored);
    let mut out = Vec::with_capacity(rest.len() + 1);
    if let Some((summary, files)) = checkpoint {
        out.push(summary_message(summary, files));
    }
    out.extend(sanitize(rest));
    out
}

type Checkpoint<'a> = (Option<(&'a str, &'a [String])>, &'a [StoredMessage]);

fn split_at_compaction(stored: &[StoredMessage]) -> Checkpoint<'_> {
    let found = stored
        .iter()
        .rposition(|entry| matches!(entry.message, Message::Compaction { .. }));
    let Some(at) = found else {
        return (None, stored);
    };
    let checkpoint = match &stored[at].message {
        Message::Compaction { summary, files, .. } => Some((summary.as_str(), files.as_slice())),
        _ => None,
    };
    (checkpoint, &stored[at.saturating_add(1)..])
}

pub fn sanitize(stored: &[StoredMessage]) -> Vec<Message> {
    let messages = || stored.iter().map(|entry| &entry.message);
    let mut has_result: HashSet<&str> = HashSet::new();
    for message in messages() {
        if let Message::Tool { tool_call_id, .. } = message {
            has_result.insert(tool_call_id.as_str());
        }
    }

    let mut requested: HashSet<&str> = HashSet::new();
    let mut out = Vec::with_capacity(stored.len());
    for message in messages() {
        match message {
            Message::Assistant {
                text,
                tool_calls,
                reasoning_content,
            } if !tool_calls.is_empty() => {
                let complete = tool_calls
                    .iter()
                    .all(|call| has_result.contains(call.id.as_str()));
                if complete {
                    requested.extend(tool_calls.iter().map(|call| call.id.as_str()));
                    out.push(message.clone());
                } else if !text.is_empty() {
                    out.push(Message::Assistant {
                        text: text.clone(),
                        tool_calls: Vec::new(),
                        reasoning_content: reasoning_content.clone(),
                    });
                }
            }
            Message::Tool { tool_call_id, .. } => {
                if requested.contains(tool_call_id.as_str()) {
                    out.push(message.clone());
                }
            }
            // The user ran it, not the model: it stays out of the context.
            Message::Shell { .. } | Message::Compaction { .. } => {}
            _ => out.push(message.clone()),
        }
    }
    out
}

const CHARS_PER_TOKEN: usize = 4;

fn estimate(text: &str) -> u64 {
    u64::try_from(text.chars().count() / CHARS_PER_TOKEN).unwrap_or(u64::MAX)
}

fn weigh(message: &Message) -> u64 {
    let mut chars = message.text().chars().count();
    if let Message::Assistant { tool_calls, .. } = message {
        for call in tool_calls {
            chars = chars.saturating_add(call.name.chars().count());
            chars = chars.saturating_add(call.arguments.chars().count());
        }
    }
    u64::try_from(chars / CHARS_PER_TOKEN).unwrap_or(u64::MAX)
}

pub fn estimate_messages(messages: &[Message]) -> u64 {
    messages.iter().map(weigh).fold(0, u64::saturating_add)
}

pub fn estimate_after(stored: &[StoredMessage], seq: i64) -> u64 {
    stored
        .iter()
        .filter(|entry| entry.seq > seq)
        .map(|entry| weigh(&entry.message))
        .fold(0, u64::saturating_add)
}

pub fn estimate_tokens(stored: &[StoredMessage]) -> u64 {
    let (checkpoint, rest) = split_at_compaction(stored);
    let carried = checkpoint.map_or(0, |(summary, _)| estimate(summary));
    rest.iter()
        .map(|entry| weigh(&entry.message))
        .fold(carried, u64::saturating_add)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Cut {
    pub from: usize,
    pub through: i64,
    pub compacted: usize,
}

impl Cut {
    pub fn span(self) -> usize {
        self.compacted.saturating_sub(self.from)
    }
}

fn is_cut_point(message: &Message) -> bool {
    !matches!(message, Message::Tool { .. })
}

pub fn cut_index(messages: &[&Message], keep_recent: u64) -> Option<usize> {
    let points: Vec<usize> = messages
        .iter()
        .enumerate()
        .filter(|(_, message)| is_cut_point(message))
        .map(|(at, _)| at)
        .collect();
    let mut cut = *points.first()?;

    let mut kept = 0u64;
    for at in (0..messages.len()).rev() {
        kept = kept.saturating_add(weigh(messages[at]));
        if kept >= keep_recent {
            let found = points
                .iter()
                .copied()
                .find(|point| *point >= at)
                .or_else(|| points.last().copied());
            if let Some(found) = found {
                cut = found;
            }
            break;
        }
    }
    (cut > 0).then_some(cut)
}

pub fn find_cut(stored: &[StoredMessage], keep_recent: u64) -> Option<Cut> {
    let marker = stored
        .iter()
        .rposition(|entry| matches!(entry.message, Message::Compaction { .. }));
    let offset = marker.map_or(0, |at| at.saturating_add(1));
    let start = &stored[offset..];
    let messages: Vec<&Message> = start.iter().map(|entry| &entry.message).collect();
    let first_kept = cut_index(&messages, keep_recent)?;
    Some(Cut {
        from: marker.unwrap_or(0),
        through: start[first_kept.saturating_sub(1)].seq,
        compacted: offset.saturating_add(first_kept),
    })
}
