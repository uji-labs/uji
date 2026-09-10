use std::error::Error;

use clap::{Parser, Subcommand};
use uji::runtime::{Runtime, events};
use uji::session::id::SessionId;
use uji::session::store::SessionStorage;
use uji::storage::interface::StorageInterface;
use uji::storage::sqlite::{SqliteStorage, default_db_path};

#[derive(Parser, Debug)]
#[command(name = "uji", version, about = "Embeddable harness — barebones TUI")]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Subcommand, Debug)]
enum Command {
    New,
    Resume {
        #[arg(long)]
        id: Option<String>,
    },
    List,
    Delete {
        id: String,
    },
}

fn main() {
    let cli = Cli::parse();
    let command = cli.command.unwrap_or(Command::New);

    let result = match command {
        Command::New => handle_new(),
        Command::Resume { id } => handle_resume(id),
        Command::List => handle_list(),
        Command::Delete { id } => handle_delete(&id),
    };

    if let Err(err) = result {
        eprintln!("uji: error: {err}");
        std::process::exit(1);
    }
}

fn open_storage() -> Result<Box<dyn SessionStorage>, Box<dyn Error>> {
    Ok(Box::new(SqliteStorage::open(default_db_path()?)?))
}

fn handle_new() -> Result<(), Box<dyn Error>> {
    let mut storage = open_storage()?;
    let session = storage.create_session("new")?;
    let runtime = Runtime::boot()?;
    runtime.emit(
        events::SESSION_CREATED,
        &[("session_id", session.id.to_string())],
    );
    runtime.run(session, storage)?;
    Ok(())
}

fn handle_resume(id: Option<String>) -> Result<(), Box<dyn Error>> {
    let mut storage = open_storage()?;
    let session = match id {
        Some(id) => {
            let session_id: SessionId = id
                .parse()
                .map_err(|_| format!("invalid session id: {id}"))?;
            storage
                .get_session(&session_id)?
                .ok_or_else(|| format!("no session with id: {id}"))?
        }
        None => match storage.latest_session()? {
            Some(session) => session,
            None => storage.create_session("resumed")?,
        },
    };
    let runtime = Runtime::boot()?;
    runtime.emit(
        events::SESSION_RESUMED,
        &[("session_id", session.id.to_string())],
    );
    runtime.run(session, storage)?;
    Ok(())
}

fn handle_list() -> Result<(), Box<dyn Error>> {
    let storage = open_storage()?;
    uji::list::run(storage)
}

fn handle_delete(id: &str) -> Result<(), Box<dyn Error>> {
    let mut storage = open_storage()?;
    let session_id: SessionId = id
        .parse()
        .map_err(|_| format!("invalid session id: {id}"))?;
    let _ = storage.delete_session(&session_id)?;
    Ok(())
}
