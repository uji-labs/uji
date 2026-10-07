local app = require("uji.core.app")
local check = require("uji.core.check")
local process = require("uji.core.system.process")
local tables = require("uji.core.tables")

uji.job = {
    start = function(opts)
        check.options(opts, "uji.job.start")
        local spec = tables.copy(opts)
        spec.argv = process.argv(opts.cmd)
        spec.cwd = opts.cwd or app.directory()
        return process.start(spec)
    end,
}
