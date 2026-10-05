local app = require("uji.core.app")
local notices = require("uji.core.notices")
local ui = require("uji.core.ui")

local M = {}

local MARKDOWN = table.concat({
    "# Heading one",
    "",
    "Some **bold**, *italic*, `code`, ~~strike~~ and a [link](https://example.com).",
    "",
    "### Small heading",
    "",
    "- first",
    "  - nested",
    "    - deeper",
    "- second",
    "",
    "1. one",
    "2. two",
    "",
    "> a quote",
    ">",
    "> > nested quote",
    "",
    "- [x] done",
    "- [ ] open",
    "",
    "```python",
    "def f(x):",
    '    return "a"  # note',
    "```",
    "",
    "| name | value |",
    "|---|---:|",
    "| a | 1 |",
    "",
    "Inline $x^2$ and display:",
    "",
    "$$\\frac{a}{b}$$",
    "",
    "---",
    "",
    "The end.",
}, "\n")

function M.numbered(prefix, count)
    local lines = {}
    for index = 1, count do
        lines[index] = prefix .. " " .. index
    end
    return table.concat(lines, "\n")
end

function M.messages()
    local session = app.session
    session:append({ type = "user", text = "Read the notes and run the build" })
    session:append({
        type = "assistant",
        text = "Reading them first.",
        tool_calls = {
            { id = "call_1", name = "read_file", arguments = '{"path":"notes.txt"}' },
            { id = "call_2", name = "mystery", arguments = '{"query":1}' },
        },
    })
    session:append({ type = "tool", tool_call_id = "call_1", name = "read_file", content = "alpha\nbeta" })
    session:append({ type = "tool", tool_call_id = "call_2", name = "mystery", content = M.numbered("row", 12) })
    session:append({ type = "tool", tool_call_id = "call_3", name = "run_command", content = "error: the build failed" })
    session:append({ type = "shell", command = "ls", output = "a.txt\nb.txt", code = 0 })
    session:append({ type = "shell", command = "false", output = "", code = 1 })
    session:append({ type = "system", text = "A system note" })
    session:append({ type = "error", text = "Something went wrong" })
    session:append({ type = "compaction", summary = "earlier work" })
    session:append({ type = "user", text = "Thanks" })
    notices.push("a notice for you")
    ui:take_notices()
    app.agent.queue = { { text = "a queued message" } }
    ui.running = { name = "run_command", line = "compiling the project" }
end

function M.markdown()
    app.session:append({ type = "user", text = "Show me markdown" })
    app.session:append({ type = "assistant", text = MARKDOWN })
    ui:delta({ text = "Streaming **partial" })
    ui.stream:reveal_all()
end

return M
