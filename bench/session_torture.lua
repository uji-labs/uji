local app = require("uji.core.app")
local scenario = require("scenario")

scenario.open()
scenario.history(1250)

torture("open a 5,000 message session", scenario.cold)

torture("scroll to the top of 5,000 messages", scenario.scroll_to_top, { budget = 10 })

torture("a 10 MB tool result", function()
    app.session:append({ type = "tool", tool_call_id = "huge", name = "run_command", content = string.rep("x", 10000000) })
    scenario.cold()
end)

torture("5,000 tool calls in one message", function()
    local calls = {}
    for index = 1, 5000 do
        calls[index] = { id = "many" .. index, name = "read_file", arguments = '{"path":"src/file' .. index .. '.rs"}' }
    end
    app.session:append({ type = "assistant", text = "", tool_calls = calls })
    scenario.cold()
end)
