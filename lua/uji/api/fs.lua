local task = require("uji.core.task")
local tool = require("uji.core.tool")

uji.fs = {
    read = task.callback(function(path)
        return tool.workspace():read(path)
    end),
    lines = task.callback(function(path, opts)
        opts = opts or {}
        return tool.workspace():lines(path, {
            offset = math.max(opts.offset or 1, 1),
            limit = opts.limit,
            max_line = opts.max_line,
        })
    end),
    write = task.callback(function(path, content)
        return tool.workspace():write(path, content)
    end),
    list = task.callback(function(path)
        return tool.workspace():list(path)
    end),
}
