mod ui;

use std::error::Error;

use crate::runtime::{Runtime, events};
use crate::session::model::Session;
use crate::session::store::SessionStorage;

pub fn run(mut storage: Box<dyn SessionStorage>) -> Result<(), Box<dyn Error>> {
    let current_dir = std::env::current_dir().map_or_else(
        |_| String::new(),
        |path| path.to_string_lossy().into_owned(),
    );

    let sessions: Vec<Session> = storage
        .list_sessions()?
        .into_iter()
        .filter(|session| session.directory == current_dir)
        .collect();

    let Some(index) = ui::pick(&sessions, &current_dir)? else {
        return Ok(());
    };

    let session = sessions[index].clone();
    let runtime = Runtime::boot()?;
    runtime.emit(
        events::SESSION_RESUMED,
        &[("session_id", session.id.to_string())],
    );
    runtime.run(session, storage)?;
    Ok(())
}
