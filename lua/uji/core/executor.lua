local class = require("uji.core.class")
local sys = require("uji.sys")
local task = require("uji.core.task")

local M = {}

local function check(items)
    if type(items) ~= "table" then
        error("a batch needs a list of items", 3)
    end
    for index, item in ipairs(items) do
        if type(item) ~= "table" then
            error("item " .. index .. " must be a table", 3)
        end
        if item.run == nil and item.resolved == nil then
            error("item " .. index .. " needs a run or a resolved outcome", 3)
        end
        if item.run ~= nil and type(item.run) ~= "function" then
            error("item " .. index .. " run must be a function", 3)
        end
    end
end

local Batch = class()

function Batch:init(items)
    check(items)
    self.items = items
    self.count = #items
    self.results, self.handles, self.state = {}, {}, {}
    self.wake, self.cancelled = nil, false
    self.done = sys.promise()
    for index, item in ipairs(items) do
        if item.resolved then
            self.state[index], self.results[index] = "done", item.resolved
        else
            self.state[index] = "pending"
        end
    end
end

function Batch:bump()
    local waiting = self.wake
    self.wake = nil
    if waiting then
        waiting:resolve()
    end
end

function Batch:left()
    local count = 0
    for index = 1, self.count do
        if self.state[index] ~= "done" then
            count = count + 1
        end
    end
    return count
end

function Batch:start(index)
    self.state[index] = "running"
    local items = self.items
    self.handles[index] = task.spawn(function()
        local ran, value = pcall(items[index].run)
        if self.state[index] ~= "running" then
            return
        end
        if ran then
            self.results[index] = { status = "completed", value = value }
        else
            self.results[index] = { status = "failed", reason = sys.message(value) }
        end
        self.state[index] = "done"
        self:bump()
    end)
end

function Batch:settle()
    if self:left() == 0 then
        return false
    end
    self.wake = sys.promise()
    self.wake:await()
    return true
end

function Batch:cancel(reason)
    if self.cancelled then
        return
    end
    self.cancelled = true
    for index = 1, self.count do
        if self.state[index] ~= "done" then
            if self.handles[index] then
                self.handles[index]:cancel()
            end
            self.state[index] = "done"
            self.results[index] = { status = "cancelled", reason = reason }
        end
    end
    self:bump()
end

function Batch:execute()
    task.spawn(function()
        local ok, err = pcall(self.run, self)
        self.done:resolve()
        if not ok then
            error(err, 0)
        end
    end)
    return self
end

function Batch:await()
    self.done:await()
    return self.results
end

local Sequential = class(Batch)

function Sequential:run()
    for index = 1, self.count do
        if self.state[index] == "pending" then
            self:start(index)
            while self.state[index] ~= "done" do
                self:settle()
            end
        end
    end
end

local Parallel = class(Batch)

function Parallel:init(items, opts)
    Batch.init(self, items)
    self.limit = opts and opts.limit or 4
    if self.limit < 1 or self.limit ~= math.floor(self.limit) then
        error("a parallel batch needs a whole limit above 0", 3)
    end
end

function Parallel:open()
    local count = 0
    for index = 1, self.count do
        if self.state[index] == "running" then
            count = count + 1
        end
    end
    return count
end

function Parallel:run()
    while true do
        local room = self.limit - self:open()
        for index = 1, self.count do
            if self.state[index] == "pending" and room > 0 then
                self:start(index)
                room = room - 1
            end
        end
        if not self:settle() then
            break
        end
    end
end

M.Sequential = Sequential
M.Parallel = Parallel

return M
