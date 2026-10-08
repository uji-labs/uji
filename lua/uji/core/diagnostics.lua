local paths = require("uji.core.paths")
local sys = require("uji.sys")
local text = require("ito").text

local FILE = "diagnostics.log"
local HEADER = "--- "
local LIMIT = 1024 * 1024
local STAMP = "^" .. HEADER .. "(%d+%-%d+%-%d+ %d+:%d+:%d+) (%S+)$"

local M = { queue = {}, last = {} }

local function file()
    local data = paths.data()
    return data and sys.fs.join(data, FILE)
end

local function entry(source, failure)
    local when = os.date("%Y-%m-%d %H:%M:%S", math.floor(sys.os.now() / 1000))
    local lines = { HEADER .. when .. " " .. source, failure.text }
    if failure.trace then
        lines[#lines + 1] = failure.trace
    end
    return table.concat(lines, "\n") .. "\n"
end

local function newest(log)
    local keep, at, cut = #log - LIMIT / 2, 0, nil
    repeat
        at = log:find("\n" .. HEADER, at + 1, true)
        cut = at or cut
    until not at or at >= keep
    return cut and log:sub(cut + 1) or log
end

local function write(path, added)
    sys.fs.mkdir(sys.fs.parent(path))
    local found = sys.fs.stat(path)
    if (found and found.size or 0) + #added > LIMIT then
        sys.fs.write(path, newest((sys.fs.read(path) or "") .. added))
    else
        sys.fs.write(path, added, { append = true })
    end
end

local function drain(path)
    while #M.queue > 0 do
        local added = table.concat(M.queue)
        M.queue = {}
        write(path, added)
    end
end

function M.capture(err)
    return { text = sys.message(err), trace = sys.traceback(2) }
end

local function record(source, failure)
    local path = file()
    if not path then
        return
    end
    M.queue[#M.queue + 1] = entry(source, failure)
    if M.writing then
        return
    end
    M.writing = sys.promise()
    sys.task.spawn(function()
        pcall(drain, path)
        local writing = M.writing
        M.writing = nil
        writing:resolve()
    end)
end

function M.report(source, failure)
    local problem = failure and failure.text
    if M.last[source] == problem then
        return
    end
    M.last[source] = problem
    if failure then
        record(source, failure)
    end
end

function M.list()
    if M.writing then
        M.writing:await()
    end
    local path = file()
    local log = path and sys.fs.read(path) or ""
    local found, bodies = {}, {}
    for _, line in ipairs(text.lines(log)) do
        local when, source = line:match(STAMP)
        if when then
            found[#found + 1] = { time = when, source = source }
            bodies[#found] = {}
        elseif #found > 0 then
            local body = bodies[#found]
            body[#body + 1] = line
        end
    end
    local entries = {}
    for index = #found, 1, -1 do
        local item = found[index]
        item.text = (table.concat(bodies[index], "\n"):gsub("%s+$", ""))
        entries[#entries + 1] = item
    end
    return entries
end

return M
