use std::error::Error;

use clap::{Parser, Subcommand};
use libuji::core::session::id::SessionId;
use libuji::core::session::store::SessionStorage;
use libuji::core::storage::interface::StorageInterface;
use libuji::core::storage::sqlite::{SqliteStorage, default_db_path};
use libuji::runtime::{Runtime, events};

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
    let mut storage = open_storage()?;
    let sessions = storage.list_sessions()?;
    if sessions.is_empty() {
        println!("no sessions");
    } else {
        for session in sessions {
            println!(
                "{}  {}  {}",
                session.id, session.title, session.time.updated
            );
        }
    }
    Ok(())
}

fn handle_delete(id: &str) -> Result<(), Box<dyn Error>> {
    let mut storage = open_storage()?;
    let session_id: SessionId = id
        .parse()
        .map_err(|_| format!("invalid session id: {id}"))?;
    if storage.delete_session(&session_id)? {
        println!("deleted session: {id}");
    } else {
        println!("no session with id: {id}");
    }
    Ok(())
}
