local sys = require("uji.sys")

local M = {}

local Server = {}
Server.__index = Server

local function head(code, headers)
    local lines = { "HTTP/1.1 " .. code .. " X", "connection: close" }
    for _, header in ipairs(headers) do
        lines[#lines + 1] = header[1] .. ": " .. header[2]
    end
    return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

local function respond(conn, reply)
    if reply.lines then
        local body = table.concat(reply.lines, "\n\n") .. "\n\n"
        return conn:write(head(200, {
            { "content-length", #body },
            { "content-type", "text/event-stream" },
        }) .. body)
    end
    if reply.drip then
        if not conn:write(head(200, { { "content-type", "text/event-stream" } })) then
            return false
        end
        while conn:write(reply.drip .. "\n\n") do
            sys.sleep(reply.every)
        end
        return false
    end
    local headers = { { "content-length", #reply.body } }
    for _, header in ipairs(reply.headers or {}) do
        headers[#headers + 1] = header
    end
    return conn:write(head(reply.status, headers) .. reply.body)
end

local function read(conn)
    local line = conn:line()
    if not line then
        return nil
    end
    local request = { path = line:match("^%S+%s+(%S+)") or "", headers = {} }
    while true do
        line = conn:line()
        local name, value = (line or ""):match("^([^:]+):%s*(.-)%s*$")
        if not name then
            break
        end
        request.headers[name:lower()] = value
    end
    local length = tonumber(request.headers["content-length"]) or 0
    local raw = length > 0 and conn:read(length) or ""
    local ok, body = pcall(sys.json.decode, raw)
    request.body = ok and body or {}
    return request
end

function Server:serve(conn)
    local request = read(conn)
    if not request then
        self.dropped = self.dropped + 1
        return
    end
    local reply = self.handler(request)
    self.requests[#self.requests + 1] = request
    if not respond(conn, reply) then
        self.dropped = self.dropped + 1
    end
    conn:close()
end

function Server:turns()
    local out = {}
    for _, request in ipairs(self.requests) do
        if M.has_tools(request) then
            out[#out + 1] = request
        end
    end
    return out
end

function M.start(handler)
    local listener = assert(sys.net.listen())
    local server = setmetatable({
        url = "http://127.0.0.1:" .. listener.port,
        handler = handler,
        requests = {},
        dropped = 0,
    }, Server)
    sys.task.spawn(function()
        while true do
            local conn = listener:accept()
            if not conn then
                return
            end
            sys.task.spawn(function()
                server:serve(conn)
            end)
        end
    end)
    return server
end

function M.has_tools(request)
    local tools = request.body.tools
    return type(tools) == "table" and #tools > 0
end

function M.system(request)
    local first = request.body.messages and request.body.messages[1]
    return first and type(first.content) == "string" and first.content or ""
end

function M.events(chunks)
    local lines = {}
    for index, chunk in ipairs(chunks) do
        lines[index] = "data: " .. sys.json.encode(chunk)
    end
    lines[#lines + 1] = "data: [DONE]"
    return { lines = lines }
end

function M.text(value)
    return M.events({
        {
            choices = { { index = 0, delta = { content = value }, finish_reason = "stop" } },
            usage = { prompt_tokens = 10, completion_tokens = 2 },
        },
    })
end

function M.tool_calls(round, calls)
    local listed = {}
    for at, call in ipairs(calls) do
        listed[at] = {
            index = at - 1,
            id = "r" .. round .. "c" .. (at - 1),
            type = "function",
            ["function"] = { name = call[1], arguments = call[2] },
        }
    end
    return M.events({
        { choices = { { index = 0, delta = { tool_calls = sys.json.array(listed) }, finish_reason = sys.json.null } } },
        {
            choices = { { index = 0, delta = {}, finish_reason = "tool_calls" } },
            usage = { prompt_tokens = 10, completion_tokens = 2 },
        },
    })
end

function M.status(code, body, headers)
    return { status = code, body = body, headers = headers }
end

function M.drip(line, every)
    return { drip = line, every = every }
end

return M
