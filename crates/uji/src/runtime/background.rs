use std::sync::Arc;

use uji_agent::llm::context::{self, Cut};
use uji_agent::llm::discover::{self, Windows};
use uji_agent::llm::{Llm, LlmConfig, Provider, Usage, summary, title};
use uji_agent::session::model::{Message, StoredMessage};

use super::signal::Signal;

pub(crate) enum CompactEvent {
    Ready {
        summary: String,
        files: Vec<String>,
        cut: Cut,
        usage: Option<Usage>,
    },
    Failed,
}

pub(crate) struct CompactRequest {
    pub(crate) client: Arc<reqwest::Client>,
    pub(crate) provider: Arc<Llm>,
    pub(crate) model: String,
    pub(crate) earlier: Vec<StoredMessage>,
    pub(crate) previous: Option<String>,
    pub(crate) carried: Vec<String>,
    pub(crate) cut: Cut,
}

pub(crate) fn compact(
    runtime: &tokio::runtime::Runtime,
    request: CompactRequest,
    sender: calloop::channel::Sender<Signal>,
) {
    runtime.spawn(async move {
        let refs: Vec<&Message> = request.earlier.iter().map(|entry| &entry.message).collect();
        let mut files = context::files_touched(&refs);
        context::merge_files(&mut files, &request.carried);
        let done = summary::generate(
            &request.client,
            request.provider.as_ref(),
            request.model,
            &refs,
            request.previous.as_deref(),
        )
        .await;
        let event = match done {
            Some(done) => CompactEvent::Ready {
                summary: done.summary,
                files,
                cut: request.cut,
                usage: done.usage,
            },
            None => CompactEvent::Failed,
        };
        let _ = sender.send(Signal::Compacted(event));
    });
}

pub(crate) enum TitleEvent {
    Ready { title: String, usage: Option<Usage> },
    Unavailable,
}

pub(crate) fn title(
    runtime: &tokio::runtime::Runtime,
    client: Arc<reqwest::Client>,
    provider: Arc<Llm>,
    model: String,
    first_message: String,
    sender: calloop::channel::Sender<Signal>,
) {
    runtime.spawn(async move {
        let event = match title::generate(&client, provider, model, &first_message).await {
            Some(titled) => TitleEvent::Ready {
                title: titled.title,
                usage: titled.usage,
            },
            None => TitleEvent::Unavailable,
        };
        let _ = sender.send(Signal::Title(event));
    });
}

pub(crate) struct ModelsEvent {
    pub(crate) provider: String,
    pub(crate) windows: Vec<Windows>,
}

pub(crate) fn model_windows(
    runtime: &tokio::runtime::Runtime,
    client: &Arc<reqwest::Client>,
    providers: Vec<Provider>,
    sender: &calloop::channel::Sender<Signal>,
) {
    for provider in providers {
        let client = Arc::clone(client);
        let sender = sender.clone();
        runtime.spawn(async move {
            let key =
                LlmConfig::for_provider(provider.id.clone(), Some(&provider), String::new(), None)
                    .resolve_key();
            let Some(windows) = discover::windows(&client, &provider, key.as_deref()).await else {
                return;
            };
            let _ = sender.send(Signal::Models(ModelsEvent {
                provider: provider.id,
                windows,
            }));
        });
    }
}
