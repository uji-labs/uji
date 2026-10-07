local class = require("uji.core.class")
local event = require("uji.core.event")
local notices = require("uji.core.notices")
local sys = require("uji.sys")
local task = require("uji.core.task")

local MAX_LINES = 2000
local KILOBYTE = 1024
local MEGABYTE = 1024 * KILOBYTE
local MAX_BYTES = 50 * KILOBYTE

local M = {}

M.MAX_LINES = MAX_LINES
M.MAX_BYTES = MAX_BYTES

local spilled = {}

event.on("before_quit", function()
    for _, path in ipairs(spilled) do
        os.remove(path)
    end
end)

function M.size(bytes)
    if bytes < KILOBYTE then
        return bytes .. "B"
    end
    if bytes < MEGABYTE then
        return string.format("%.1fKB", bytes / KILOBYTE)
    end
    return string.format("%.1fMB", bytes / MEGABYTE)
end

local Capture = class()

function Capture:init(opts)
    opts = opts or {}
    self.max_lines = opts.lines or MAX_LINES
    self.max_bytes = opts.bytes or MAX_BYTES
    self.path = opts.spill
    self.lines = {}
    self.first = 1
    self.last = 0
    self.bytes = 0
    self.total = 0
    self.partial = nil
end

function Capture:spill()
    if not self.path then
        self.path = os.tmpname()
        spilled[#spilled + 1] = self.path
    end
    self.file = io.open(self.path, "w") or false
    for at = self.first, self.last do
        self:write(self.lines[at])
    end
end

function Capture:write(line)
    if self.file and not self.file:write(line, "\n") then
        self.file:close()
        self.file = false
    end
end

function Capture:drop()
    self.bytes = self.bytes - #self.lines[self.first] - 1
    self.lines[self.first] = nil
    self.first = self.first + 1
end

function Capture:over()
    return self.last - self.first + 1 > self.max_lines or self.bytes - 1 > self.max_bytes
end

function Capture:push(line)
    if self.file ~= nil then
        self:write(line)
    end
    self.total = self.total + 1
    if self.partial then
        self:drop()
        self.partial = nil
    end
    self.last = self.last + 1
    self.lines[self.last] = line
    self.bytes = self.bytes + #line + 1
    if self:over() and self.file == nil then
        self:spill()
    end
    while self:over() and self.last > self.first do
        self:drop()
    end
    if #line > self.max_bytes then
        local tail = line:sub(-self.max_bytes):gsub("^[\128-\191]+", "")
        self.partial = #line
        self.lines[self.last] = tail
        self.bytes = #tail + 1
    end
end

function Capture:since(seen)
    local from = math.max(seen + 1, self.first)
    local lines = {}
    for at = from, self.last do
        lines[#lines + 1] = self.lines[at]
    end
    return lines, from - seen - 1, self.last
end

function Capture:finish()
    if self.file then
        self.file:close()
    end
    local text = table.concat(self.lines, "\n", self.first, self.last)
    local kept = self.last - self.first + 1
    if kept == self.total and not self.partial then
        return text
    end
    local saved = self.file and ". Full output: " .. self.path or ""
    local note
    if self.partial then
        local shown = M.size(#self.lines[self.last])
        note = string.format("[Showing last %s of line %d (line is %s)%s]", shown, self.total, M.size(self.partial), saved)
    else
        local limit = kept < self.max_lines and " (" .. M.size(self.max_bytes) .. " limit)" or ""
        note = string.format("[Showing lines %d-%d of %d%s%s]", self.total - kept + 1, self.total, self.total, limit, saved)
    end
    return (text ~= "" and text .. "\n\n" or "") .. note
end

M.Capture = Capture

function M.argv(cmd)
    if type(cmd) == "string" then
        return { "sh", "-c", cmd }
    end
    if type(cmd) ~= "table" then
        error("cmd must be a string or a list of strings", 3)
    end
    if #cmd == 0 then
        error("cmd must not be empty", 3)
    end
    local out = {}
    for index, part in ipairs(cmd) do
        out[index] = tostring(part)
    end
    return out
end

function M.spawn(spec)
    local argv = spec.shell and { "sh", "-c", spec.shell } or spec.argv
    if not argv or #argv == 0 then
        return nil, "no program to run"
    end
    local proc, err = sys.proc.spawn(argv, { cwd = spec.cwd, env = spec.env })
    if not proc then
        return nil, err
    end
    if not spec.stdin then
        proc:close()
    end
    return proc
end

function M.watch(proc, timeout, on_line)
    local finished, exit = task.timeout(timeout, function()
        for line, stream in proc:lines() do
            on_line(stream, line)
        end
        return proc:wait()
    end)
    if not finished then
        proc:kill()
        proc:wait()
        return { timed_out = true }
    end
    return { code = exit.code or -1, signal = exit.signal }
end

local function call(handler, ...)
    if handler then
        local ok, err = pcall(handler, ...)
        if not ok then
            notices.push("job: " .. tostring(err))
        end
    end
end

function M.start(spec)
    local stopped = false
    local proc, err = M.spawn({ argv = spec.argv, cwd = spec.cwd, stdin = true })
    if not proc then
        task.spawn(function()
            call(spec.on_stderr, "spawn: " .. tostring(err))
            call(spec.on_exit, -1)
        end)
        return {
            send = function() end,
            close = function() end,
            stop = function() end,
        }
    end
    task.spawn(function()
        local result = M.watch(proc, spec.timeout, function(stream, line)
            call(stream == "stderr" and spec.on_stderr or spec.on_stdout, line)
        end)
        if result.timed_out then
            return call(spec.on_exit, -1, "timeout")
        end
        if stopped then
            return call(spec.on_exit, -1, "stopped")
        end
        call(spec.on_exit, result.code)
    end)
    local queue = task.sequence()
    return {
        send = function(text)
            local data = tostring(text)
            if data:sub(-1) ~= "\n" then
                data = data .. "\n"
            end
            queue(function()
                proc:write(data)
            end)
        end,
        close = function()
            queue(function()
                proc:close()
            end)
        end,
        stop = function()
            stopped = true
            proc:kill()
        end,
    }
end

function M.run(spec, on_line)
    local proc, err = M.spawn(spec)
    if not proc then
        return nil, err
    end
    return M.watch(proc, spec.timeout, on_line)
end

return M
