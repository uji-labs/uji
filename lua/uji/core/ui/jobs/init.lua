local class = require("uji.core.class")
local ito = require("ito")
local jobs = require("uji.core.jobs")
local keys = require("uji.core.ui.keys")
local list = require("uji.utils.list")
local sys = require("uji.sys")
local task = require("uji.core.task")

local ROWS = 5
local LINGER = 30

local Jobs = class()

function Jobs:init(ui)
    self.ui = ui
    self.rows = {}
    self.selected = nil
    self.dropped = {}
    self.hint = nil
    ito.observable(self)
end

local function showing(job, now)
    if job.state == "running" then
        return true
    end
    if job.state == "finished" and job.code == 0 then
        return false
    end
    return job.ended == nil or now - job.ended < LINGER
end

function Jobs:refresh()
    local rows, now = {}, sys.os.clock()
    for _, job in ipairs(jobs.list()) do
        if showing(job, now) and not self.dropped[job.id] then
            rows = list.appended(rows, {
                id = job.id,
                name = string.format(self.ui.theme.tokens.text.job, job.id),
                detail = job.command,
                elapsed = math.floor((job.ended or now) - job.started),
                running = job.state == "running",
            })
        end
    end
    table.sort(rows, function(left, right)
        if left.running ~= right.running then
            return left.running
        end
        return left.id < right.id
    end)
    if #rows > ROWS then
        rows = { table.unpack(rows, 1, ROWS) }
    end
    self.rows = rows
end

function Jobs:busy()
    return #jobs.running() > 0 or #self.rows > 0
end

function Jobs:index()
    for at, row in ipairs(self.rows) do
        if row.id == self.selected then
            return at
        end
    end
end

function Jobs:key(chord, writing)
    local key = chord.key
    if #self.rows == 0 or writing then
        return false
    end
    if keys.is_char(chord) and key ~= "x" then
        self.selected = nil
        return false
    end
    local at = self:index()
    if not at then
        if key ~= "up" then
            self.selected = nil
            return false
        end
        self.selected = self.rows[1].id
        return true
    end
    if key == "up" then
        self.selected = self.rows[math.max(at - 1, 1)].id
    elseif key == "down" then
        self.selected = self.rows[at + 1] and self.rows[at + 1].id
    elseif key == "esc" then
        self.selected = nil
    elseif key == "enter" then
        self:open(self.rows[at])
    elseif key == "x" then
        self:stop_or_drop(self.rows[at])
    else
        return false
    end
    return true
end

function Jobs:stop_or_drop(row)
    if row.running then
        jobs.stop(jobs.get(row.id))
    else
        self.dropped[row.id] = true
        self.selected = nil
        self:refresh()
    end
end

function Jobs:open(row)
    local job = row and jobs.get(row.id)
    if not job then
        return
    end
    local Output = require("uji.core.ui.views.output")
    local Overlay = require("uji.core.ui.views.overlay")
    self.ui:present(Overlay(function()
        return Output({ name = row.name, job = job })
    end))
end

function Jobs:finished(job)
    if job.state ~= "finished" or job.code ~= 0 then
        return
    end
    local shown = { text = self.ui.theme.tokens.text.jobs_hint }
    self.hint = shown
    task.spawn(function()
        sys.sleep(LINGER)
        if self.hint == shown then
            self.hint = nil
        end
    end)
end

return Jobs
