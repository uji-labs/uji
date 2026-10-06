local class = require("uji.core.class")
local event = require("uji.core.event")
local sys = require("uji.sys")

local STATUSES = { queued = true, running = true, done = true, failed = true }
local FIELDS = { "label", "line", "detail", "group" }

local Task = class()

function Task:init(progress, item)
    self.progress = progress
    self.item = item
end

function Task:status(status)
    if not STATUSES[status] then
        error("task status `" .. tostring(status) .. "` is not queued, running, done or failed", 3)
    end
    local item, now = self.item, sys.os.clock()
    item.status = status
    if status ~= "queued" then
        item.started = item.started or now
    end
    if status == "done" or status == "failed" then
        item.finished = item.finished or now
    end
end

function Task:update(fields)
    if type(fields) ~= "table" then
        error("task:update needs a table", 2)
    end
    for _, key in ipairs(FIELDS) do
        if fields[key] ~= nil then
            self.item[key] = tostring(fields[key])
        end
    end
    if fields.status ~= nil then
        self:status(fields.status)
    end
    self.progress:emit("tasks")
end

function Task:done(detail)
    self:update({ status = "done", detail = detail })
end

function Task:fail(detail)
    self:update({ status = "failed", detail = detail })
end

local Progress = class()

function Progress:init(name)
    self.name = name
    self.line = ""
    self.tasks = {}
end

function Progress:snapshot()
    local out = {}
    for index, item in ipairs(self.tasks) do
        out[index] = {
            label = item.label,
            status = item.status,
            line = item.line,
            detail = item.detail,
            group = item.group,
            started = item.started,
            finished = item.finished,
        }
    end
    return out
end

function Progress:emit(changed)
    event.emit("tool_progress", { name = self.name, line = self.line, tasks = self:snapshot(), changed = changed })
end

function Progress:report(line)
    self.line = tostring(line or "")
    self:emit("line")
end

function Progress:task(label, opts)
    if type(label) ~= "string" then
        error("ctx.task needs a label", 2)
    end
    if opts ~= nil and type(opts) ~= "table" then
        error("ctx.task options must be a table", 2)
    end
    opts = opts or {}
    local item = { label = label, line = "", detail = "" }
    local task = Task(self, item)
    self.tasks[#self.tasks + 1] = item
    task:update({ status = opts.status or "running", group = opts.group, line = opts.line, detail = opts.detail })
    return task
end

return Progress
