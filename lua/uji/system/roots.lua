local class = require("uji.class")
local path = require("uji.system.path")
local sys = require("uji.sys")

local SNIFF_BYTES = 8192
local PREVIEW_LINE = 2000

local Roots = class()

function Roots:init(cwd, extra, confined)
    self.cwd = cwd
    self.extra = extra or {}
    self.confined = confined ~= false
end

function Roots:outside(target)
    return target .. " is outside the working directory (" .. self.cwd .. "); tools can only reach files under it"
end

function Roots:failed(action, target, err)
    if tostring(err):find("Permission denied", 1, true) then
        return self:outside(target)
    end
    return action .. " " .. target .. ": " .. tostring(err)
end

local function relative(root, target)
    if path.absolute(target) then
        return path.strip_prefix(target, root)
    end
    if path.stays_within(target) then
        return path.normalize(target)
    end
end

function Roots:candidates()
    local roots = { self.cwd }
    for _, root in ipairs(self.extra) do
        roots[#roots + 1] = root
    end
    if not self.confined then
        roots[#roots + 1] = "/"
    end
    return roots
end

local function real(full)
    local resolved = sys.fs.realpath(full)
    if resolved then
        return resolved
    end
    local parent = path.parent(full)
    if parent == full then
        return full
    end
    return path.join(real(parent), path.base(full))
end

function Roots:resolve(target)
    for _, root in ipairs(self:candidates()) do
        local rel = relative(root, target)
        if rel then
            local full = rel == "." and root or path.join(root, rel)
            local root_real = sys.fs.realpath(root) or root
            if root == "/" or path.within(real(full), root_real) then
                return full
            end
            return nil, self:outside(target)
        end
    end
    return nil, self:outside(target)
end

function Roots:read(target)
    local full, err = self:resolve(target)
    if not full then
        return nil, err
    end
    local bytes, failure = sys.fs.read(full)
    if not bytes then
        return nil, self:failed("read", target, failure)
    end
    return bytes
end

function Roots:excerpt(target, window)
    local full, err = self:resolve(target)
    if not full then
        return nil, err
    end
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

function Roots:lines(target, window)
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

function Roots:write(target, content)
    local full, err = self:resolve(target)
    if not full then
        return nil, err
    end
    local created = sys.fs.stat(full) == nil
    local parent = path.parent(full)
    local made, failure = sys.fs.mkdir(parent)
    if not made then
        return nil, self:failed("mkdir", target, failure)
    end
    local written, problem = sys.fs.write(full, content)
    if not written then
        return nil, self:failed("write", target, problem)
    end
    return { created = created }
end

function Roots:around(target, line, count)
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

return Roots
