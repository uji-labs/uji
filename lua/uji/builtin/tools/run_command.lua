local field = require("uji.builtin.tools.field")
local process = require("uji.core.system.process")
local shell = require("uji.core.system.shell")

local TIMEOUT = 120

uji.tool.add("run_command", {
    description = "Run a shell command and return its combined stdout and stderr, plus the exit code when it "
        .. "is non-zero. Every command starts in the working directory, so there is no need to `cd` "
        .. "into it first. Use it to build, test, run linters, search with `rg`, `grep` or `find`, and "
        .. "explore with `ls`. Read and change files with `read_file`, `edit_file` and `write_file`. "
        .. "The command is non-interactive: it cannot prompt, and it is killed at the timeout. Output is "
        .. string.format(
            "truncated to the last %d lines or %s, whichever is hit first, and then the full output is saved to a temp file.",
            process.MAX_LINES,
            process.size(process.MAX_BYTES)
        ),
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
    parts = function(args)
        return shell.commands(field.text(args, "command"))
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
        local output = process.Capture()
        local function line(text)
            output:push(text)
            ctx.progress(text)
        end
        local job = uji.job.start({
            cmd = field.text(args, "command"),
            cwd = uji.session.info().directory,
            timeout = timeout,
            on_stdout = line,
            on_stderr = line,
            on_exit = function(code, reason)
                local text = output:finish()
                if reason == "timeout" then
                    return ctx.done("error: command timed out after " .. timeout .. "s")
                end
                if code == 0 then
                    return ctx.done(text:find("%S") and text or text .. "(no output, exit code 0)")
                end
                ctx.done((text == "" and "" or text .. "\n") .. "(exit code " .. code .. ")")
            end,
        })
        job.close()
        return job.stop
    end,
})
