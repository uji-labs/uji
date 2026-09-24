use super::catalog::Budget;
use super::context;
use super::{DEFAULT_MAX_OUTPUT, Effort, Llm, LlmRequest, Retention, Usage};
use crate::session::model::Message;

const FORMAT: &str = "## Goal\n\
[What the user is trying to accomplish. Multiple items if the session covers several tasks.]\n\n\
## Constraints & Preferences\n\
- [Constraints, preferences or requirements the user stated, or \"(none)\"]\n\n\
## Progress\n\
### Done\n\
- [x] [Completed work]\n\
### In Progress\n\
- [ ] [Current work]\n\
### Blocked\n\
- [What is preventing progress, or \"(none)\"]\n\n\
## Key Decisions\n\
- **[Decision]**: [Brief rationale]\n\n\
## Next Steps\n\
1. [Ordered list of what should happen next]\n\n\
## Critical Context\n\
- [Data, examples or references needed to continue, or \"(none)\"]\n\n\
Keep each section concise. Preserve exact file paths, function names, commands and error \
strings verbatim.";

const PROMPT: &str = "You compact coding sessions. The messages above are a conversation to \
summarise. Write a structured checkpoint that another agent will use to continue the work \
without the original transcript. Do not invent anything that is not in the transcript. \
Reply with the summary alone, no preamble.\n\n\
Use this EXACT format:\n\n";

const UPDATE_PROMPT: &str = "You maintain a rolling checkpoint of a coding session. The \
existing checkpoint is in <previous-summary> tags; the messages after it are NEW activity \
to fold in.\n\n\
RULES:\n\
- PRESERVE every fact from the previous checkpoint unless it became wrong.\n\
- MOVE items from \"In Progress\" to \"Done\" as they complete.\n\
- UPDATE \"Next Steps\" to reflect the current state.\n\
- PRESERVE exact file paths, function names, commands and error strings.\n\
- Drop items only when they are no longer relevant.\n\n\
Reply with the updated checkpoint alone, no preamble.\n\n\
Use this EXACT format:\n\n";

const MAX_INPUT: usize = 200_000;

pub struct Summarized {
    pub summary: String,
    pub usage: Option<Usage>,
}

pub struct Compacted {
    pub messages: Vec<Message>,
    pub summary: String,
    pub usage: Option<Usage>,
    pub count: usize,
}

pub async fn compact(
    client: &reqwest::Client,
    provider: &Llm,
    model: String,
    budget: Budget,
    keep_recent: u64,
    mut messages: Vec<Message>,
) -> Option<Compacted> {
    if !budget.overflows(context::estimate_messages(&messages)) {
        return None;
    }
    let at = context::cut_index(&messages.iter().collect::<Vec<_>>(), keep_recent)?;
    let carried = messages
        .first()
        .map_or_else(Vec::new, context::previous_files);
    let previous = messages
        .first()
        .and_then(|message| context::previous_summary(message))
        .map(str::to_string);
    let skip = usize::from(previous.is_some());
    let head: Vec<&Message> = messages[skip..at].iter().collect();
    let mut files = context::files_touched(&head);
    context::merge_files(&mut files, &carried);
    let summarised = generate(client, provider, model, &head, previous.as_deref()).await?;
    let count = head.len();
    let tail = messages.split_off(at);
    messages.clear();
    messages.push(context::summary_message(&summarised.summary, &files));
    messages.extend(tail);
    Some(Compacted {
        messages,
        summary: summarised.summary,
        usage: summarised.usage,
        count,
    })
}

pub async fn generate(
    client: &reqwest::Client,
    provider: &Llm,
    model: String,
    messages: &[&Message],
    previous: Option<&str>,
) -> Option<Summarized> {
    let transcript = transcript(messages);
    if transcript.trim().is_empty() {
        return None;
    }
    let (instructions, text) = match previous {
        Some(previous) => (
            UPDATE_PROMPT,
            format!("<previous-summary>\n{previous}\n</previous-summary>\n\n{transcript}"),
        ),
        None => (PROMPT, transcript),
    };
    let system = format!("{instructions}{FORMAT}");
    let messages = [Message::User { text }];
    let request = LlmRequest {
        model: &model,
        system: Some(&system),
        messages: &messages,
        tools: &[],
        effort: Effort::Off,
        cache: Retention::Off,
        max_output: DEFAULT_MAX_OUTPUT,
    };
    let response = provider.call(client, &request).await.ok()?;
    let summary = response.text.trim().to_string();
    if summary.is_empty() {
        return None;
    }
    Some(Summarized {
        summary,
        usage: response.usage,
    })
}

fn transcript(messages: &[&Message]) -> String {
    let mut chunks: Vec<String> = Vec::new();
    let mut budget = MAX_INPUT;
    for message in messages.iter().rev() {
        let label = match message {
            Message::User { .. } => "user",
            Message::Assistant { .. } => "assistant",
            Message::Tool { name, .. } => name.as_str(),
            Message::System { .. } => "system",
            // Never reached the model, so it has nothing to do with the summary.
            Message::Shell { .. } | Message::Context { .. } => continue,
            Message::Error { .. } => "error",
            Message::Compaction { .. } => "earlier summary",
        };
        let text = message.text();
        if text.trim().is_empty() {
            continue;
        }
        let chunk = format!("[{label}] {text}\n\n");
        let size = chunk.chars().count();
        if size > budget {
            break;
        }
        budget = budget.saturating_sub(size);
        chunks.push(chunk);
    }
    chunks.reverse();
    chunks.concat()
}
