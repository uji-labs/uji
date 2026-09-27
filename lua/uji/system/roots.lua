local class = require("uji.class")
local path = require("uji.system.path")
local sys = require("uji.sys")

local SNIFF_BYTES = 8192
local PREVIEW_LINE = 2000
local REPLACEMENT = "\239\191\189"

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

local function lossy_cut(line, max)
    if #line <= max then
        return line, false
    end
    local kept = line:sub(1, max)
    local lead = #kept
    while lead > 0 and kept:byte(lead) >= 128 and kept:byte(lead) < 192 do
        lead = lead - 1
    end
    if lead > 0 then
        local byte = kept:byte(lead)
        local need = byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 1
        if lead + need - 1 > #kept then
            kept = kept:sub(1, lead - 1) .. REPLACEMENT
        end
    end
    return kept, true
end

function Roots:text(target)
    local full, err = self:resolve(target)
    if not full then
        return nil, err
    end
    local stat = sys.fs.stat(full)
    if stat and stat.type == "dir" then
        return nil, target .. " is a directory, not a file"
    end
    local bytes, failure = sys.fs.read(full)
    if not bytes then
        return nil, self:failed("read", target, failure)
    end
    if bytes:sub(1, SNIFF_BYTES):find("\0", 1, true) then
        return nil, target .. " looks like a binary file"
    end
    return bytes
end

local function each_line(text)
    local at = 1
    local size = #text
    return function()
        if at > size then
            return nil
        end
        local stop = text:find("\n", at, true)
        local line
        if stop then
            line = text:sub(at, stop - 1)
            at = stop + 1
        else
            line = text:sub(at)
            at = size + 1
        end
        return line
    end
end

function Roots:lines(target, window)
    local text, err = self:text(target)
    if not text then
        return nil, err
    end
    local offset = window.offset or 1
    local limit = window.limit or math.huge
    local max = window.max_line or math.huge
    local out = { lines = {}, cut = {}, total = 0 }
    for line in each_line(text) do
        out.total = out.total + 1
        if out.total >= offset and #out.lines < limit then
            local kept, truncated = lossy_cut(line, max)
            out.lines[#out.lines + 1] = kept
            if truncated then
                out.cut[#out.lines] = true
            end
        end
    end
    return out
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
    local text, err = self:text(target)
    if not text then
        return nil, err
    end
    local start = math.max(line - 1, 0) - math.floor(count / 4)
    start = math.max(start, 0)
    local stop = start + count
    local out = {}
    local at = 0
    for current in each_line(text) do
        if at >= stop then
            break
        end
        at = at + 1
        if at > start then
            local shown = lossy_cut(current, PREVIEW_LINE):gsub("\r$", "")
            out[#out + 1] = string.format("%5d| %s", at, shown)
        end
    end
    return out
end

return Roots
