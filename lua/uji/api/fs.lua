local app = require("uji.core.app")
local Files = require("uji.core.system.files")
local task = require("uji.core.task")

local function files()
    return Files(app.directory())
end

uji.fs = {
    read = task.callback(function(path)
        return files():read(path)
    end),
    lines = task.callback(function(path, opts)
        opts = opts or {}
        return files():lines(path, {
            offset = math.max(opts.offset or 1, 1),
            limit = opts.limit,
            max_line = opts.max_line,
        })
    end),
    write = task.callback(function(path, content)
        return files():write(path, content)
    end),
    list = task.callback(function(path)
        return files():list(path)
    end),
    glob = task.callback(function(pattern)
        return files():glob(pattern)
    end),
}
