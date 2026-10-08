local class = require("uji.core.class")
local event = require("uji.core.event")
local id = require("uji.core.id")
local ito = require("ito")
local list = require("uji.utils.list")
local sys = require("uji.sys")
local tables = require("uji.core.tables")
local tokens = require("uji.core.agent.tokens")

local PLACEHOLDERS = { [""] = true, untitled = true, new = true, resumed = true }

local function usage()
    return { input = 0, output = 0, cache_read = 0, cache_write = 0 }
end

local function summed(into, other)
    return {
        input = into.input + (other.input or 0),
        output = into.output + (other.output or 0),
        cache_read = into.cache_read + (other.cache_read or 0),
        cache_write = into.cache_write + (other.cache_write or 0),
    }
end

local function prefix(value)
    return (value.input or 0) + (value.cache_read or 0) + (value.cache_write or 0)
end

local function encode(message)
    local copy = tables.copy(message)
    if copy.type == "assistant" and copy.tool_calls and #copy.tool_calls == 0 then
        copy.tool_calls = nil
    end
    if copy.type == "compaction" then
        copy.files = sys.json.array(copy.files or {})
    end
    return sys.json.encode(copy)
end

local Session = class()

function Session:init(store, row)
    self.store = store
    self.id = row.id
    self.title = row.title
    self.directory = row.directory
    self.parent = row.parent
    self.updated = row.time_updated
    self.tally = { usage = usage(), last = usage(), turns = 0 }
    self.reported_input = 0
    self.reported_seq = 0
    ito.observable(self)
end

function Session:entries()
    if self.stored then
        return self.stored
    end
    local stored = {}
    local rows = self.store.db:query("SELECT id, seq, time_created, data FROM messages WHERE session_id = ? ORDER BY seq", { self.id })
    for index, row in ipairs(rows) do
        stored[index] = {
            id = row.id,
            seq = row.seq,
            time = row.time_created,
            message = sys.json.decode(row.data, { nulls = false }),
        }
    end
    self.stored = stored
    return stored
end

function Session:messages()
    return list.mapped(self:entries(), function(entry)
        return entry.message
    end)
end

function Session:last_seq()
    local stored = self:entries()
    return #stored > 0 and stored[#stored].seq or 0
end

function Session:append(message)
    local stored = self:entries()
    local now = sys.os.now()
    local entry = { id = id.new(), seq = self:last_seq() + 1, time = now, message = message }
    local db = self.store.db
    local ok, err = pcall(db.transaction, db, function()
        db:exec(
            "INSERT INTO messages (id, session_id, seq, type, time_created, data) VALUES (?, ?, ?, ?, ?, ?)",
            { entry.id, self.id, entry.seq, message.type, now, encode(message) }
        )
        db:exec("UPDATE sessions SET time_updated = ? WHERE id = ?", { now, self.id })
    end)
    if message.type == "compaction" then
        self.reported_input = 0
        self.reported_seq = 0
    end
    self.stored = list.appended(stored, entry)
    event.emit("message_appended", { type = message.type, text = tokens.text(message) })
    if not ok then
        return entry, "failed to persist " .. message.type .. " message: " .. sys.message(err)
    end
    return entry
end

function Session:rename(title)
    self.store.db:exec("UPDATE sessions SET title = ? WHERE id = ?", { title, self.id })
    self.title = title
end

function Session:untitled()
    return PLACEHOLDERS[(self.title or ""):match("^%s*(.-)%s*$")] == true
end

function Session:child(title)
    return self.store:create_session(title or self.title, self.id)
end

function Session:unanswered_calls()
    local stored = self:entries()
    local answered = {}
    for index = #stored, 1, -1 do
        local message = stored[index].message
        if message.type == "tool" then
            answered[message.tool_call_id] = true
        elseif message.type == "assistant" then
            return list.filtered(message.tool_calls or {}, function(call)
                return not answered[call.id]
            end)
        else
            break
        end
    end
    return {}
end

function Session:add_cost(spent)
    local tally = self.tally
    self.tally = { usage = summed(tally.usage, spent), last = tally.last, turns = tally.turns }
end

function Session:add_usage(spent)
    if prefix(spent) > 0 then
        self.reported_input = prefix(spent)
        self.reported_seq = self:last_seq()
    end
    local tally = self.tally
    self.tally = {
        usage = summed(tally.usage, spent),
        last = {
            input = spent.input or 0,
            output = spent.output or 0,
            cache_read = spent.cache_read or 0,
            cache_write = spent.cache_write or 0,
        },
        turns = tally.turns + 1,
    }
end

function Session:used_tokens()
    local stored = self:entries()
    if self.reported_input > 0 then
        return self.reported_input + tokens.after(stored, self.reported_seq)
    end
    return tokens.total(stored)
end

Session.prefix = prefix
Session.encode = encode

return Session
