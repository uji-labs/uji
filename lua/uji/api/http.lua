local sys = require("uji.sys")
local task = require("uji.task")

local TIMEOUT = 30
local IDLE = 120

local function streamed(opts)
    local idle = opts.idle or IDLE
    local body, err = sys.net.open({
        url = opts.url,
        method = opts.method,
        headers = opts.headers,
        body = opts.body,
        timeout = opts.timeout,
        idle = idle,
    })
    if not body then
        return nil, err
    end
    local deadline = sys.os.clock() + idle
    local lines = {}
    while true do
        local line, problem = body:line(math.max(deadline - sys.os.clock(), 0))
        if line == false then
            return nil, "no data arrived for " .. idle .. " seconds"
        end
        if not line then
            if problem then
                return nil, problem
            end
            break
        end
        lines[#lines + 1] = line
        local ok, progressed = pcall(opts.on_line, line)
        if not ok then
            return nil, tostring(progressed)
        end
        if progressed ~= false then
            deadline = sys.os.clock() + idle
        end
    end
    return { status = body.status, headers = body.headers, body = table.concat(lines, "\n") }
end

local function request(opts)
    if type(opts) ~= "table" or type(opts.url) ~= "string" then
        error("uji.http.request needs a url", 3)
    end
    if opts.on_line then
        return streamed(opts)
    end
    return sys.net.request({
        url = opts.url,
        method = opts.method,
        headers = opts.headers,
        body = opts.body,
        timeout = opts.timeout or TIMEOUT,
    })
end

return {
    request = task.callback(request),
}
