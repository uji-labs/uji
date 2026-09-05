use diesel::insert_into;
use diesel::prelude::*;
use diesel::sqlite::SqliteConnection;

use crate::storage::error::{Result, StorageError};
use crate::storage::interface::StorageInterface;
use crate::storage::schema::{messages, sessions, settings};

use super::id::{MessageId, SessionId, now_millis};
use super::model::{Message, Session, StoredMessage, Time};
use super::sql::{MessageRow, SessionRow};

pub trait SessionStorage {
    fn create_session(&mut self, title: &str) -> Result<Session>;
    fn get_session(&mut self, id: &SessionId) -> Result<Option<Session>>;
    fn latest_session(&mut self) -> Result<Option<Session>>;
    fn list_sessions(&mut self) -> Result<Vec<Session>>;
    fn delete_session(&mut self, id: &SessionId) -> Result<bool>;

    fn append_message(&mut self, session_id: &SessionId, message: Message)
    -> Result<StoredMessage>;
    fn messages(&mut self, session_id: &SessionId) -> Result<Vec<StoredMessage>>;
    fn message(&mut self, id: &MessageId) -> Result<Option<(SessionId, StoredMessage)>>;

    fn get_setting(&mut self, key: &str) -> Result<Option<String>>;
    fn set_setting(&mut self, key: &str, value: &str) -> Result<()>;
}

impl<T: StorageInterface<Connection = SqliteConnection>> SessionStorage for T {
    fn create_session(&mut self, title: &str) -> Result<Session> {
        let conn = self.get_connection();
        let id = SessionId::new();
        let now = now_millis();
        let directory = std::env::current_dir()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default();

        insert_into(sessions::table)
            .values((
                sessions::id.eq(id.to_string()),
                sessions::parent_id.eq(Option::<String>::None),
                sessions::title.eq(title),
                sessions::directory.eq(directory.clone()),
                sessions::time_created.eq(now),
                sessions::time_updated.eq(now),
            ))
            .execute(conn)?;

        Ok(Session {
            id,
            parent_id: None,
            title: title.to_string(),
            directory,
            time: Time {
                created: now,
                updated: now,
            },
        })
    }

    fn get_session(&mut self, id: &SessionId) -> Result<Option<Session>> {
        let conn = self.get_connection();
        let row = sessions::table
            .find(id.to_string())
            .first::<SessionRow>(conn)
            .optional()?;
        Ok(row.map(Session::try_from).transpose()?)
    }

    fn latest_session(&mut self) -> Result<Option<Session>> {
        let conn = self.get_connection();
        let row = sessions::table
            .order_by(sessions::time_updated.desc())
            .then_order_by(sessions::id.desc())
            .first::<SessionRow>(conn)
            .optional()?;
        Ok(row.map(Session::try_from).transpose()?)
    }

    fn list_sessions(&mut self) -> Result<Vec<Session>> {
        let conn = self.get_connection();
        let rows = sessions::table
            .order_by(sessions::time_updated.desc())
            .load::<SessionRow>(conn)?;
        rows.into_iter()
            .map(|row| Session::try_from(row).map_err(StorageError::from))
            .collect()
    }

    fn delete_session(&mut self, id: &SessionId) -> Result<bool> {
        let conn = self.get_connection();
        let deleted = diesel::delete(sessions::table.find(id.to_string())).execute(conn)?;
        Ok(deleted > 0)
    }

    fn append_message(
        &mut self,
        session_id: &SessionId,
        message: Message,
    ) -> Result<StoredMessage> {
        let conn = self.get_connection();
        let last_seq: Option<i64> = messages::table
            .filter(messages::session_id.eq(session_id.to_string()))
            .select(diesel::dsl::max(messages::seq))
            .first(conn)?;
        let seq = last_seq.unwrap_or(0) + 1;

        let id = MessageId::new();
        let now = now_millis();
        let data = serde_json::to_string(&message)?;

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

        Ok(StoredMessage {
            id,
            seq,
            time_created: now,
            message,
        })
    }

    fn messages(&mut self, session_id: &SessionId) -> Result<Vec<StoredMessage>> {
        let conn = self.get_connection();
        let rows = messages::table
            .filter(messages::session_id.eq(session_id.to_string()))
            .order_by(messages::seq.asc())
            .load::<MessageRow>(conn)?;
        rows.into_iter().map(StoredMessage::try_from).collect()
    }

    fn message(&mut self, id: &MessageId) -> Result<Option<(SessionId, StoredMessage)>> {
        let conn = self.get_connection();
        let row = messages::table
            .find(id.to_string())
            .first::<MessageRow>(conn)
            .optional()?;
        match row {
            Some(row) => {
                let session_id = row.session_id.parse()?;
                let stored = StoredMessage::try_from(row)?;
                Ok(Some((session_id, stored)))
            }
            None => Ok(None),
        }
    }

    fn get_setting(&mut self, key: &str) -> Result<Option<String>> {
        let conn = self.get_connection();
        let value = settings::table
            .find(key.to_string())
            .select(settings::value)
            .first::<String>(conn)
            .optional()?;
        Ok(value)
    }

    fn set_setting(&mut self, key: &str, value: &str) -> Result<()> {
        let conn = self.get_connection();
        insert_into(settings::table)
            .values((settings::key.eq(key), settings::value.eq(value)))
            .on_conflict(settings::key)
            .do_update()
            .set(settings::value.eq(value))
            .execute(conn)?;
        Ok(())
    }
}
