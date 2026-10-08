local field = require("uji.builtin.tools.field")
local jobs = require("uji.core.jobs")
local process = require("uji.core.system.process")

uji.tool.add("run_command", {
    description = "Run a shell command and return its combined stdout and stderr, plus the exit code when it "
        .. "is non-zero. Every command starts in the working directory, so there is no need to `cd` "
        .. "into it first. Use it to build, test, run linters, search with `rg`, `grep` or `find`, and "
        .. "explore with `ls`. Read files with `read_file`, not `cat`, `head`, `tail` or `sed -n`. Change "
        .. "them with `edit_file`, not `sed` or `awk`, and create them with `write_file`, not `echo` or "
        .. "`cat` with a redirect. "
        .. "The command is non-interactive: it cannot prompt. Output is "
        .. string.format(
            "truncated to the last %d lines or %s, whichever is hit first, and then the full output is saved to a temp file. ",
            process.MAX_LINES,
            process.size(process.MAX_BYTES)
        )
        .. "Set `run_in_background` for a dev server, a watch build or anything else you do not need to "
        .. "wait for: it returns at once with a job id. A command still running at its timeout moves to the "
        .. "background instead of being stopped. uji tells you when a background job ends, so do not poll "
        .. "`job_output` for it; read its output then, and stop it with `stop_job`.",
    parameters = {
        type = "object",
        properties = {
            command = {
                type = "string",
                description = "Shell command, for example `cargo test -p uji`.",
            },
            timeout = {
                type = "integer",
                description = "Seconds before the command moves to the background. Defaults to 120. "
                    .. "With run_in_background, the seconds before it is stopped, 30 minutes by default.",
                minimum = 1,
            },
            run_in_background = {
                type = "boolean",
                description = "Start the command as a background job and return at once.",
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
        label = "Shell",
        question = "Would you like to run the following command?",
    },
    run = function(args, ctx)
        local missing = field.missing(args, "command")
        if missing then
            return missing
        end
        local background = args.run_in_background == true
        local job, err = jobs.start({
            command = field.text(args, "command"),
            cwd = uji.session.info().directory,
            timeout = field.count(args, "timeout"),
            background = background,
            done = ctx.done,
            progress = ctx.progress,
        })
        if not job then
            return "error: " .. err
        end
        if background then
            return jobs.started(job)
        end
        return function()
            jobs.stop(job)
        end
    end,
})
