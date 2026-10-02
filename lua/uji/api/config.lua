local app = require("uji.core.app")
local packs = require("uji.core.packs")
local path = require("uji.core.system.path")
local sys = require("uji.sys")
local task = require("uji.core.task")

local PROJECT = ".uji"

local function collect(dir, project, out)
    for _, entry in ipairs(sys.fs.list(dir) or {}) do
        if entry.type == "file" then
            local full = path.join(dir, entry.name)
            local text = sys.fs.read(full)
            if text then
                out[#out + 1] = { name = entry.name, path = full, text = text, project = project }
            end
        end
    end
end

local function nearest(folder)
    local dir = app.directory()
    while true do
        local candidate = path.join(path.join(dir, PROJECT), folder)
        local stat = sys.fs.stat(candidate)
        if stat and stat.type == "dir" then
            return candidate
        end
        local parent = path.parent(dir)
        if parent == dir then
            return nil
        end
        dir = parent
    end
end

local function files(folder, opts)
    if type(folder) ~= "string" or folder == "" or path.absolute(folder) or not path.stays_within(folder) then
        error("uji.config.files needs a folder name inside the config directory", 3)
    end
    local out = {}
    for _, root in ipairs(packs.list()) do
        collect(path.join(root, folder), false, out)
    end
    if opts and opts.project then
        local dir = nearest(folder)
        if dir then
            collect(dir, true, out)
        end
    end
    return out
end

uji.config = {
    files = task.callback(files),
}
