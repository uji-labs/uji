use uji_agent::llm::StreamEvent;

use super::auth::AuthEvent;
use super::background::{CompactEvent, ModelsEvent, TitleEvent};
use super::job::JobEvent;
use super::loop_data::shell::ShellEvent;

pub(crate) enum Signal {
    Llm(StreamEvent),
    Job(JobEvent),
    Shell(ShellEvent),
    Auth(AuthEvent),
    Title(TitleEvent),
    Compacted(CompactEvent),
    Models(ModelsEvent),
}
