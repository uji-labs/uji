local paths = require("uji.core.paths")
local sys = require("uji.sys")
local task = require("uji.core.task")

local PRIVATE = tonumber("600", 8)

local function file(name, api)
    if type(name) ~= "string" or name == "" or sys.fs.name(name) ~= name then
        error(api .. " needs a file name", 4)
    end
    local dir = paths.data()
    return dir and sys.fs.join(dir, name), dir
end

uji.data = {
    read = task.callback(function(name)
        local path = file(name, "uji.data.read")
        if not path then
            return nil, "there is no data directory"
        end
        return sys.fs.read(path)
    end),
    write = task.callback(function(name, text)
        local path, dir = file(name, "uji.data.write")
        if type(text) ~= "string" then
            error("uji.data.write needs the text to write", 3)
        end
        if not path then
            return nil, "there is no data directory"
        end
        sys.fs.mkdir(dir)
        return sys.fs.write(path, text, { mode = PRIVATE })
    end),
}
