local class = require("uji.core.class")
local id = require("uji.core.id")
local sys = require("uji.sys")
local Session = require("uji.core.store.session")

local UNTITLED = "untitled"

local MIGRATIONS = {
    [[
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            directory TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            seq INTEGER NOT NULL,
            type TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            data TEXT NOT NULL
        );
        CREATE UNIQUE INDEX IF NOT EXISTS messages_session_seq ON messages(session_id, seq);
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
    ]],
    [[ALTER TABLE sessions ADD COLUMN parent TEXT REFERENCES sessions(id) ON DELETE CASCADE]],
}

local COLUMNS = "id, title, directory, parent, time_created, time_updated"

local Store = class()

Store.UNTITLED = UNTITLED

function Store:init(path)
    self.drafts = {}
    local parent = path:match("^(.*)/[^/]*$")
    if parent and parent ~= "" then
        sys.fs.mkdir(parent)
    end
    local db, err = sys.db.open(path)
    if not db then
        error("cannot open " .. path .. ": " .. tostring(err), 0)
    end
    self.path = path
    self.db = db
    db:exec("PRAGMA busy_timeout = 5000")
    db:exec("PRAGMA journal_mode = WAL")
    db:exec("PRAGMA synchronous = NORMAL")
    db:exec("PRAGMA foreign_keys = ON")
    self:migrate()
end

function Store:migrate()
    local version = self.db:query("PRAGMA user_version")[1].user_version
    for index = version + 1, #MIGRATIONS do
        self.db:transaction(function()
            self.db:exec(MIGRATIONS[index])
            self.db:exec("PRAGMA user_version = " .. index)
        end)
    end
end

function Store:setting(key)
    local row = self.db:query("SELECT value FROM settings WHERE key = ?", { key })[1]
    return row and row.value
end

function Store:set_setting(key, value)
    self.db:exec("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", { key, value })
end

function Store:create_session(title, parent, key)
    local now = sys.os.now()
    local row = {
        id = key or id.new(),
        title = title or UNTITLED,
        directory = sys.os.cwd(),
        time_created = now,
        time_updated = now,
        parent = parent,
    }
    local session = Session(self, row)
    session.pending = true
    self.drafts[session.id] = session
    return session
end

-- Commit ancestors and the first message in the same transaction.
function Store:persist(session, inserted)
    if not session.pending then
        return
    end
    if session.parent then
        self:persist(assert(self:session(session.parent), "missing parent session"), inserted)
    end
    self.db:exec(
        "INSERT INTO sessions (id, title, directory, parent, time_created, time_updated) VALUES (?, ?, ?, ?, ?, ?)",
        { session.id, session.title, session.directory, session.parent or sys.db.null, session.created, session.updated }
    )
    inserted[#inserted + 1] = session
end

function Store:session(key)
    if self.drafts[key] then
        return self.drafts[key]
    end
    local row = self.db:query("SELECT " .. COLUMNS .. " FROM sessions WHERE id = ?", { key })[1]
    return row and Session(self, row)
end

function Store:latest(directory)
    local sessions = self.db:query("SELECT " .. COLUMNS .. " FROM sessions ORDER BY time_updated DESC, id DESC")
    local parent = {}
    for _, row in ipairs(sessions) do
        parent[row.id] = row.parent
    end
    local history = {}
    for _, row in ipairs(self.db:query("SELECT DISTINCT session_id FROM messages")) do
        local owner = row.session_id
        while owner and not history[owner] do
            history[owner] = true
            owner = parent[owner]
        end
    end
    for _, row in ipairs(sessions) do
        if not row.parent and row.directory == directory and history[row.id] then
            return Session(self, row)
        end
    end
    return nil
end

-- True when descendant is key itself or below it in the parent chain.
function Store:contains(key, descendant)
    local current = descendant
    while current do
        if current == key then
            return true
        end
        local session = self:session(current)
        current = session and session.parent
    end
    return false
end

function Store:sessions()
    local out = {}
    for _, row in ipairs(self.db:query("SELECT " .. COLUMNS .. " FROM sessions WHERE parent IS NULL ORDER BY time_updated DESC, id DESC")) do
        out[#out + 1] = Session(self, row)
    end
    return out
end

function Store:delete(key)
    local changed = self.db:exec("DELETE FROM sessions WHERE id = ?", { key })
    return changed > 0
end

return Store
