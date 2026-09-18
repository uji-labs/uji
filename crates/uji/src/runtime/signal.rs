use uji_agent::llm::StreamEvent;

use super::auth::AuthEvent;
use super::background::{CompactEvent, TitleEvent};
use super::job::JobEvent;

pub(crate) enum Signal {
    Llm(StreamEvent),
    Job(JobEvent),
    Shell(JobEvent),
    Auth(AuthEvent),
    Title(TitleEvent),
    Compacted(CompactEvent),
}
