local agent = require("support.agent")
local app = require("uji.core.app")
local screen = require("support.ui")
local server = require("support.server")
local sys = require("uji.sys")
local Transcript = require("uji.core.ui.transcript")
local ui = require("uji.core.ui")

local POLL = 0.01

local M = {}

M.REPLY = [==[
## Why the parser stalls

The tokenizer reads the whole buffer before it emits anything, so a **large file** blocks the
first frame. Splitting the read into chunks keeps the cost at $O(n)$ with a bounded \(k\):

1. Read up to `CHUNK` bytes.
2. Emit every complete token.
3. Carry the tail into the next read.

```python
def tokens(source, chunk=4096):
    tail = ""
    for start in range(0, len(source), chunk):
        text = tail + source[start:start + chunk]
        *done, tail = text.split(" ")
        yield from done  # complete tokens only
    if tail:
        yield tail
```

| case | before | after |
|------|--------|-------|
| 1 MB | 420 ms | 12 ms |
| 10 MB | 4.1 s | 95 ms |

> The fix keeps memory flat, since only one chunk and its tail are alive at once.
]==]

M.OUTPUT = string.rep("src/parser/tokens.rs:42:    let mut tail = String::with_capacity(CHUNK);\n", 60)

function M.open()
    screen.open()
    ui:render()
end

function M.history(turns)
    for index = 1, turns do
        app.session:append({ type = "user", text = "Turn " .. index .. ": why does the parser stall on big files?" })
        app.session:append({
            type = "assistant",
            text = "",
            tool_calls = {
                { id = "call" .. index, name = "read_file", arguments = '{"path":"src/parser/tokens.rs"}' },
            },
        })
        app.session:append({ type = "tool", tool_call_id = "call" .. index, name = "read_file", content = M.OUTPUT })
        app.session:append({ type = "assistant", text = M.REPLY })
    end
end

function M.cold()
    app.session.stored = nil
    ui.views.messages.transcript = Transcript()
    ui.scroll:follow()
    ui:render()
end

function M.scroll_to_top()
    local frames = 1
    M.cold()
    local _, height = ui.screen:size()
    while ui.scroll.resolved > 0 do
        ui.scroll:up(height)
        ui:render()
        frames = frames + 1
    end
    return frames
end

function M.tokens(source)
    local out = {}
    for token in source:gmatch("%S*%s*") do
        if token ~= "" then
            out[#out + 1] = token
        end
    end
    return out
end

function M.stream(tokens)
    ui:clear_stream()
    for _, token in ipairs(tokens) do
        ui:delta({ kind = "text", text = token })
        ui.stream:reveal_step()
        ui:render()
    end
    ui:clear_stream()
    return #tokens
end

function M.chunks(tokens)
    local chunks = {}
    for index, token in ipairs(tokens) do
        chunks[index] = { choices = { { index = 0, delta = { content = token }, finish_reason = sys.json.null } } }
    end
    chunks[#chunks + 1] = {
        choices = { { index = 0, delta = {}, finish_reason = "stop" } },
        usage = { prompt_tokens = 10, completion_tokens = #tokens },
    }
    return chunks
end

function M.serve(reply)
    local served = agent.serve(type(reply) == "function" and reply or function()
        return reply
    end)
    agent.provider(served.url, 1000000)
    uji.model.use({ provider = "test", model = "m" })
    agent.allow_all()
    return served
end

function M.turn(prompt)
    local finished = sys.promise()
    local listener = uji.on("turn_finished", function()
        finished:resolve()
    end)
    uji.session.submit(prompt)
    finished:await()
    uji.off("turn_finished", listener)
end

function M.idle()
    while app.agent.state ~= "idle" or #app.agent.queue > 0 do
        sys.sleep(POLL)
    end
end

function M.call(name, args)
    M.serve(function(round)
        if round == 0 then
            return server.tool_calls(round, { { name, sys.json.encode(args) } })
        end
        return server.text("done")
    end)
    M.turn("use " .. name)
    local results = agent.tool_results(agent.messages())
    return results[#results]
end

M.events = server.events
M.text = server.text
M.tool_calls = server.tool_calls
M.drip = server.drip
M.messages = agent.messages
M.last_answer = agent.last_answer

return M
