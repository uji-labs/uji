local field = require("uji.builtin.tools.field")
local jobs = require("uji.core.jobs")
local ui = require("uji.core.ui")

local PARAMETERS = {
    type = "object",
    properties = {
        id = { type = "integer", description = "The job id run_command gave.", minimum = 1 },
    },
    required = { "id" },
    additionalProperties = false,
}

local function subject(args)
    local id = field.count(args, "id")
    return id and string.format(ui.theme.tokens.text.job, id)
end

local function lookup(args)
    local id = field.count(args, "id")
    local job = id and jobs.get(id)
    if not job then
        return nil, "error: there is no job " .. tostring(args.id) .. "; use an id run_command gave"
    end
    return job
end

uji.tool.add("job_output", {
    description = "Read what a background job printed since the last time you read it, with its status and exit "
        .. "code. uji tells you when a job ends, so call this then rather than in a loop.",
    parameters = PARAMETERS,
    subject = subject,
    policy = "allow",
    display = { verb = "Read output of", question = "Read the output of a background job?" },
    run = function(args)
        local job, err = lookup(args)
        return job and jobs.output(job) or err
    end,
})

uji.tool.add("stop_job", {
    description = "Stop a background job that is still running.",
    parameters = PARAMETERS,
    subject = subject,
    policy = "allow",
    display = { verb = "Stopped", question = "Stop a background job?" },
    run = function(args)
        local job, err = lookup(args)
        if not job then
            return err
        end
        if jobs.stop(job) then
            return "stopped job " .. job.id
        end
        return "error: job " .. job.id .. " is not running"
    end,
})
