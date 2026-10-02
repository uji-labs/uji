local params = require("support.params")
local sys = require("uji.sys")

local M = {
    root = params.root,
    work = params.root .. "/work",
    cfg = params.root .. "/cfg",
    data = params.root .. "/data",
    db = params.root .. "/uji.db",
    bin = params.bin,
    fixtures = params.lua .. "/fixtures",
}

local function parent(path)
    return path:match("^(.*)/[^/]*$")
end

function M.write(path, content)
    assert(sys.fs.mkdir(parent(path)))
    assert(sys.fs.write(path, content))
end

function M.file(relative, content)
    M.write(M.work .. "/" .. relative, content)
end

function M.read(path)
    return assert(sys.fs.read(path))
end

function M.lines(path)
    local out = {}
    for line in M.read(path):gmatch("[^\n]+") do
        out[#out + 1] = line
    end
    return out
end

function M.dir(name)
    local root = M.root .. "/" .. name
    for _, sub in ipairs({ "cfg", "work", "data" }) do
        assert(sys.fs.mkdir(root .. "/" .. sub))
    end
    return {
        root = root,
        cfg = root .. "/cfg",
        work = root .. "/work",
        data = root .. "/data",
        db = root .. "/uji.db",
    }
end

return M
