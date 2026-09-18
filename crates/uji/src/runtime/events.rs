use strum::IntoStaticStr;

#[derive(Debug, Clone, Copy, PartialEq, Eq, IntoStaticStr)]
#[strum(serialize_all = "snake_case")]
pub enum Event {
    SessionCreated,
    SessionResumed,
    SessionTitled,
    MessageSubmitted,
    QueueChanged,
    MessageAppended,
    RenderMessage,
    ShellStarted,
    ShellFinished,
    ToolCall,
    ToolStarted,
    ToolFinished,
    TurnFinished,
    ModelChanged,
    Compacted,
    Error,
    StatusChanged,
    Tick,
    Quit,
}

impl Event {
    pub fn name(self) -> &'static str {
        self.into()
    }
}
