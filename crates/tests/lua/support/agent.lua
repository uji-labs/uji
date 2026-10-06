local app = require("uji.core.app")
local screen = require("support.ui")
local server = require("support.server")
local sys = require("uji.sys")
local ui = require("uji.core.ui")

local M = {}

function M.provider(url, context)
    uji.provider.add({
        id = "test",
        name = "Test",
        api = uji.api.openai(),
        base_url = url .. "/v1",
        models = { { id = "m", context = context, output = 1000 } },
    })
end

function M.allow_all()
    local allow = { default = "allow" }
    uji.tool.policy({
        default = "allow",
        read_file = allow,
        edit_file = allow,
        write_file = allow,
        run_command = allow,
    })
end

function M.serve(script)
    local round = 0
    return server.start(function(request)
        if not server.has_tools(request) then
            local compacting = server.system(request):find("compact", 1, true)
            return server.text(compacting and "SUMMARY OF EARLIER WORK" or "Title")
        end
        local reply = script(round)
        round = round + 1
        return reply
    end)
end

local function answer(keys)
    local next, answered = 1, nil
    sys.task.spawn(function()
        while keys[next] do
            local modal = ui.modal
            if modal and modal ~= answered and modal.mode == "confirm" then
                answered = modal
                screen.press(keys[next])
                next = next + 1
            end
            sys.sleep(0.01)
        end
    end)
end

M.answer = answer

function M.messages()
    local rows = app.store.db:query("SELECT data FROM messages WHERE session_id = ? ORDER BY seq", { app.session.id })
    local out = {}
    for index, row in ipairs(rows) do
        out[index] = sys.json.decode(row.data, { nulls = false })
    end
    return out
end

function M.run(opts)
    M.provider(opts.url, opts.context or 100000)
    uji.model.use({ provider = "test", model = "m" })
    app.session:rename("test")
    for _, message in ipairs(opts.history or {}) do
        app.session:append(message)
    end
    answer(opts.answers or {})
    local finished = sys.promise()
    uji.on("turn_finished", function()
        if #app.agent.queue == 0 then
            finished:resolve()
        end
    end)
    uji.session.submit(opts.prompt or "go")
    finished:await()
    return M.messages()
end

function M.tool_results(messages)
    local out = {}
    for _, message in ipairs(messages) do
        if message.type == "tool" then
            out[#out + 1] = message.content
        end
    end
    return out
end

function M.last_answer(messages)
    local last = messages[#messages]
    if last and last.type == "assistant" and #(last.tool_calls or {}) == 0 then
        return last.text
    end
end

function M.last_error(messages)
    local last = messages[#messages]
    return last and last.type == "error" and last.text or nil
end

return M
