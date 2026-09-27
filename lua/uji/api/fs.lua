local app = require("uji.app")
local task = require("uji.task")
local tool = require("uji.tool")

local function files()
    return tool.files(app.session and app.session.directory or nil)
end

return {
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
}
