local check = require("uji.core.check")
local jobs = require("uji.core.jobs")
local list = require("uji.utils.list")

local SETTINGS = { wake = "boolean", max = "number", limit = "number" }

local function row(job)
    return { id = job.id, command = job.command, state = job.state, code = job.code, status = job:status(), tail = job:tail() }
end

uji.jobs = {
    list = function()
        return list.mapped(jobs.list(), row)
    end,
    stop = function(id)
        return jobs.stop(jobs.get(id))
    end,
    configure = function(opts)
        check.options(opts, "uji.jobs.configure")
        for key, value in pairs(opts) do
            local kind = SETTINGS[key]
            if not kind then
                error("unknown option: " .. tostring(key), 2)
            end
            if type(value) ~= kind or (kind == "number" and value <= 0) then
                error(key .. (kind == "number" and " must be a number above 0" or " must be true or false"), 2)
            end
        end
        jobs.configure(opts)
    end,
}
