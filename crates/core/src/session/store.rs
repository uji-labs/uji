use diesel::insert_into;
use diesel::prelude::*;

use crate::storage::error::{Result, StorageError};
use crate::storage::schema::{messages, sessions, settings};
use crate::storage::sqlite::SqliteStorage;

use super::id::{MessageId, SessionId, now_millis};
use super::model::{Message, Session, Stamp, StoredMessage, Time};
use super::sql::{MessageRow, SessionRow};

pub trait SessionStorage {
    fn create_session(&mut self, title: &str) -> Result<Session>;
    fn get_session(&mut self, id: &SessionId) -> Result<Option<Session>>;
    fn latest_session(&mut self) -> Result<Option<Session>>;
    fn list_sessions(&mut self) -> Result<Vec<Session>>;
    fn delete_session(&mut self, id: &SessionId) -> Result<bool>;
    fn rename_session(&mut self, id: &SessionId, title: &str) -> Result<()>;

    fn append_message(&mut self, session_id: &SessionId, message: &Message) -> Result<Stamp>;
    fn messages(&mut self, session_id: &SessionId) -> Result<Vec<StoredMessage>>;

    fn get_setting(&mut self, key: &Setting) -> Result<Option<String>>;
    fn set_setting(&mut self, key: &Setting, value: &str) -> Result<()>;
}

/// A persisted setting key. Variants carry their own storage key so a reader and
/// a writer cannot silently disagree on a string.
#[derive(Debug, PartialEq, Eq)]
pub enum Setting {
    Provider,
    Model,
    BaseUrl,
    Effort,
    ModelFor(String),
}

impl Setting {
    pub fn key(&self) -> std::borrow::Cow<'_, str> {
        match self {
            Self::Provider => "llm.provider".into(),
            Self::Model => "llm.model".into(),
            Self::BaseUrl => "llm.base_url".into(),
            Self::Effort => "llm.effort".into(),
            Self::ModelFor(provider) => format!("llm.model.{provider}").into(),
        }
    }
}

impl SessionStorage for SqliteStorage {
    fn create_session(&mut self, title: &str) -> Result<Session> {
        let conn = self.connection();
        let id = SessionId::new();
        let now = now_millis();
        let directory = current_directory();

        insert_into(sessions::table)
            .values((
                sessions::id.eq(id.to_string()),
                sessions::title.eq(title),
                sessions::directory.eq(directory.clone()),
                sessions::time_created.eq(now),
                sessions::time_updated.eq(now),
            ))
            .execute(conn)?;

        Ok(Session {
            id,
            title: title.to_string(),
            directory,
            time: Time {
                created: now,
                updated: now,
            },
        })
    }

    fn get_session(&mut self, id: &SessionId) -> Result<Option<Session>> {
        let conn = self.connection();
        let row = sessions::table
            .find(id.to_string())
            .first::<SessionRow>(conn)
            .optional()?;
        Ok(row.map(Session::try_from).transpose()?)
    }

    fn latest_session(&mut self) -> Result<Option<Session>> {
        let conn = self.connection();
        let row = sessions::table
            .filter(sessions::directory.eq(current_directory()))
            .order_by(sessions::time_updated.desc())
            .then_order_by(sessions::id.desc())
            .first::<SessionRow>(conn)
            .optional()?;
        Ok(row.map(Session::try_from).transpose()?)
    }

    fn list_sessions(&mut self) -> Result<Vec<Session>> {
        let conn = self.connection();
        let rows = sessions::table
            .order_by(sessions::time_updated.desc())
            .load::<SessionRow>(conn)?;
        rows.into_iter()
            .map(|row| Session::try_from(row).map_err(StorageError::from))
            .collect()
    }

    fn delete_session(&mut self, id: &SessionId) -> Result<bool> {
        let conn = self.connection();
        let deleted = diesel::delete(sessions::table.find(id.to_string())).execute(conn)?;
        Ok(deleted > 0)
    }

    fn rename_session(&mut self, id: &SessionId, title: &str) -> Result<()> {
        let conn = self.connection();
        diesel::update(sessions::table.find(id.to_string()))
            .set(sessions::title.eq(title))
            .execute(conn)?;
        Ok(())
    }

    fn append_message(&mut self, session_id: &SessionId, message: &Message) -> Result<Stamp> {
        let conn = self.connection();
        let id = MessageId::new();
        let now = now_millis();
        let data = serde_json::to_string(message)?;

        let seq = conn.immediate_transaction::<i64, StorageError, _>(|conn| {
            let last_seq: Option<i64> = messages::table
                .filter(messages::session_id.eq(session_id.to_string()))
                .select(diesel::dsl::max(messages::seq))
                .first(conn)?;
            let seq = last_seq.unwrap_or(0) + 1;

            insert_into(messages::table)
                .values((
                    messages::id.eq(id.to_string()),
                    messages::session_id.eq(session_id.to_string()),
                    messages::seq.eq(seq),
                    messages::kind.eq(message.type_name()),
                    messages::time_created.eq(now),
                    messages::data.eq(data),
                ))
                .execute(conn)?;

            diesel::update(sessions::table.find(session_id.to_string()))
                .set(sessions::time_updated.eq(now))
                .execute(conn)?;

            Ok(seq)
        })?;

        Ok(Stamp {
            id,
            seq,
            time_created: now,
        })
    }

    fn messages(&mut self, session_id: &SessionId) -> Result<Vec<StoredMessage>> {
        let conn = self.connection();
        let rows = messages::table
            .filter(messages::session_id.eq(session_id.to_string()))
            .order_by(messages::seq.asc())
            .load::<MessageRow>(conn)?;
        rows.into_iter().map(StoredMessage::try_from).collect()
    }

    fn get_setting(&mut self, key: &Setting) -> Result<Option<String>> {
        let conn = self.connection();
        let value = settings::table
            .find(key.key().into_owned())
            .select(settings::value)
            .first::<String>(conn)
            .optional()?;
        Ok(value)
    }

    fn set_setting(&mut self, key: &Setting, value: &str) -> Result<()> {
        let conn = self.connection();
        let key = key.key().into_owned();
        insert_into(settings::table)
            .values((settings::key.eq(&key), settings::value.eq(value)))
            .on_conflict(settings::key)
            .do_update()
            .set(settings::value.eq(value))
            .execute(conn)?;
        Ok(())
    }
}

fn current_directory() -> String {
    std::env::current_dir()
        .map(|path| path.to_string_lossy().into_owned())
        .unwrap_or_default()
}
