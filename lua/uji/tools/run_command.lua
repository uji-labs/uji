local field = require("uji.tools.field")
local process = require("uji.system.process")

local MAX_OUTPUT = 24000
local TIMEOUT = 120

local spilled = {}

uji.on("before_quit", function()
    for _, path in ipairs(spilled) do
        os.remove(path)
    end
end)

local Output = {}
Output.__index = Output

function Output.new(budget)
    return setmetatable({ lines = {}, first = 1, last = 0, bytes = 0, budget = budget, dropped = 0 }, Output)
end

function Output:spill()
    self.path = os.tmpname()
    spilled[#spilled + 1] = self.path
    self.file = io.open(self.path, "w") or false
    for at = self.first, self.last do
        self:write(self.lines[at])
    end
end

function Output:write(line)
    if self.file and not self.file:write(line, "\n") then
        self.file:close()
        self.file = false
    end
end

function Output:push(line)
    self:write(line)
    self.last = self.last + 1
    self.lines[self.last] = line
    self.bytes = self.bytes + #line + 1
    while self.bytes > self.budget and self.last > self.first do
        if self.file == nil then
            self:spill()
        end
        self.bytes = self.bytes - #self.lines[self.first] - 1
        self.lines[self.first] = nil
        self.first = self.first + 1
        self.dropped = self.dropped + 1
    end
end

function Output:finish()
    local kept = table.concat(self.lines, "\n", self.first, self.last)
    if self.dropped == 0 then
        return kept
    end
    local head = "… " .. self.dropped .. " earlier lines dropped"
    if self.file and self.file:close() then
        head = head .. "; full output in " .. self.path
    end
    return head .. "\n" .. kept
end

return {
    description = "Run a shell command and return its combined stdout and stderr, plus the exit code when it "
        .. "is non-zero. Every command starts in the working directory, so there is no need to `cd` "
        .. "into it first. Use it to build, test, run linters, search with `rg`, `grep` or `find`, and "
        .. "explore with `ls`. Read and change files with `read_file`, `edit_file` and `write_file`. "
        .. "The command is non-interactive: it cannot prompt, and it is killed at the timeout.",
    parameters = {
        type = "object",
        properties = {
            command = {
                type = "string",
                description = "Shell command, for example `cargo test -p uji`.",
            },
            timeout = {
                type = "integer",
                description = "Seconds before the command is killed. Defaults to 120.",
                minimum = 1,
            },
        },
        required = { "command" },
        additionalProperties = false,
    },
    subject = function(args)
        return field.text(args, "command")
    end,
    policy = "ask",
    display = {
        verb = "Ran",
        question = "Would you like to run the following command?",
    },
    run = function(args, ctx)
        local missing = field.missing(args, "command")
        if missing then
            return missing
        end
        local timeout = math.max(field.count(args, "timeout") or TIMEOUT, 1)
        local output = Output.new(MAX_OUTPUT)
        local exit, err = process.run({
            shell = field.text(args, "command"),
            cwd = uji.session.info().directory,
            timeout = timeout,
        }, function(_, line)
            output:push(line)
            ctx.progress(line)
        end)
        local text = output:finish()
        if not exit then
            return "spawn: " .. tostring(err) .. "\n(exit code -1)"
        end
        if exit.timed_out then
            return "error: command timed out after " .. timeout .. "s"
        end
        if exit.code == 0 then
            return text:find("%S") and text or text .. "(no output, exit code 0)"
        end
        return (text == "" and "" or text .. "\n") .. "(exit code " .. exit.code .. ")"
    end,
}
