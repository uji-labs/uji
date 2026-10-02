local class = require("uji.core.class")
local sys = require("uji.sys")
local task = require("uji.core.task")

local M = {}

local Capture = class()

function Capture:init(budget, spill)
    self.lines = {}
    self.first = 1
    self.last = 0
    self.bytes = 0
    self.budget = budget
    self.dropped = 0
    if spill then
        self.spill = io.open(spill, "w")
        self.spill_path = self.spill and spill or nil
    end
end

function Capture:push(line)
    if self.spill and not self.spill:write(line, "\n") then
        self.spill:close()
        self.spill = nil
        self.spill_path = nil
    end
    self.bytes = self.bytes + #line + 1
    self.last = self.last + 1
    self.lines[self.last] = line
    while self.bytes > self.budget and self.last > self.first do
        local gone = self.lines[self.first]
        self.lines[self.first] = nil
        self.first = self.first + 1
        self.bytes = self.bytes - (#gone + 1)
        self.dropped = self.dropped + 1
    end
end

function Capture:finish()
    local spilled
    if self.spill then
        self.spill:close()
        spilled = self.spill_path
        self.spill = nil
    end
    local head = ""
    if self.dropped > 0 then
        head = "… " .. self.dropped .. " earlier lines dropped"
        if spilled then
            head = head .. "; full output in " .. spilled .. "\n"
        else
            head = head .. "\n"
        end
    end
    local kept = {}
    for index = self.first, self.last do
        kept[#kept + 1] = self.lines[index]
    end
    return head .. table.concat(kept, "\n")
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

function M.run(spec, on_line)
    local proc, err = M.spawn(spec)
    if not proc then
        return nil, err
    end
    return M.watch(proc, spec.timeout, on_line)
end

return M
