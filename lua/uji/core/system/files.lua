local class = require("uji.core.class")
local sys = require("uji.sys")

local SNIFF_BYTES = 8192
local PREVIEW_LINE = 2000

local Files = class()

function Files:init(cwd)
    self.cwd = cwd
end

function Files:failed(action, target, err)
    return action .. " " .. target .. ": " .. tostring(err)
end

function Files:resolve(target)
    return sys.fs.resolve(self.cwd, target)
end

function Files:glob(pattern)
    return sys.fs.glob(self.cwd, pattern)
end

function Files:read(target)
    local bytes, failure = sys.fs.read(self:resolve(target))
    if not bytes then
        return nil, self:failed("read", target, failure)
    end
    return bytes
end

function Files:list(target)
    local entries, failure = sys.fs.list(self:resolve(target))
    if not entries then
        return nil, self:failed("list", target, failure)
    end
    return entries
end

function Files:excerpt(target, window)
    local full = self:resolve(target)
    local stat = sys.fs.stat(full)
    if stat and stat.type == "dir" then
        return nil, target .. " is a directory, not a file"
    end
    window.sniff = SNIFF_BYTES
    local read, failure = sys.fs.lines(full, window)
    if not read then
        return nil, self:failed("read", target, failure)
    end
    if read.binary then
        return nil, target .. " looks like a binary file"
    end
    return read
end

function Files:lines(target, window)
    local read, err = self:excerpt(target, {
        from = window.offset or 1,
        count = window.limit,
        max = window.max_line,
        total = true,
    })
    if not read then
        return nil, err
    end
    local cut = {}
    for _, index in ipairs(read.cut) do
        cut[index] = true
    end
    return { lines = read.lines, cut = cut, total = read.total }
end

function Files:write(target, content)
    local full = self:resolve(target)
    local created = sys.fs.stat(full) == nil
    local made, failure = sys.fs.mkdir(sys.fs.parent(full) or full)
    if not made then
        return nil, self:failed("mkdir", target, failure)
    end
    local written, problem = sys.fs.write(full, content)
    if not written then
        return nil, self:failed("write", target, problem)
    end
    return { created = created }
end

function Files:around(target, line, count)
    local start = math.max(math.max(line - 1, 0) - math.floor(count / 4), 0)
    local read, err = self:excerpt(target, { from = start + 1, count = count, max = PREVIEW_LINE })
    if not read then
        return nil, err
    end
    local out = {}
    for index, text in ipairs(read.lines) do
        out[index] = string.format("%5d| %s", start + index, (text:gsub("\r$", "")))
    end
    return out
end

return Files
