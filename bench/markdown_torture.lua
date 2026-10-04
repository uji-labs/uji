local app = require("uji.core.app")
local scenario = require("scenario")
local ui = require("uji.core.ui")

local function nested_list(depth)
    local lines = {}
    for level = 1, depth do
        lines[level] = string.rep("  ", level - 1) .. "- item " .. level
    end
    return table.concat(lines, "\n")
end

local function table_rows(count)
    local rows = { "| name | value | note |", "|------|-------|------|" }
    for index = 1, count do
        rows[#rows + 1] = "| row " .. index .. " | " .. index .. " | `x` |"
    end
    return table.concat(rows, "\n")
end

local function show(reply)
    app.session:append({ type = "assistant", text = reply })
    scenario.cold()
    ui:clear_stream()
    ui:delta({ kind = "text", text = reply })
    ui.stream:reveal_all()
    ui:render()
    ui:clear_stream()
end

scenario.open()

local replies = {
    { "a list nested 1,000 deep", nested_list(1000) },
    { "quotes nested 1,000 deep", string.rep("> ", 1000) .. "deep" },
    { "a table with 20,000 rows", table_rows(20000) },
    { "a 1 MB line", string.rep("word ", 200000) },
    { "an unclosed fence with 50,000 lines", "```python\n" .. string.rep("total = total + item * 3.5  # w\n", 50000) },
    { "50,000 emphasis markers", string.rep("*a **b ", 50000) },
    { "10,000 code spans and math brackets", string.rep("`\\(x\\)` \\(y ", 10000) },
    { "math braces 5,000 deep", "$" .. string.rep("{", 5000) .. "x" .. string.rep("}", 5000) .. "$" },
    { "50,000 unclosed links", string.rep("[a](", 50000) },
    { "100 KB of invalid UTF-8", string.rep("\255\254abc ", 20000) },
    { "100 KB of emoji and combining marks", string.rep("👩‍👩‍👧‍👦 é̃ ", 10000) },
    { "a 1 MB line in a python fence", "```python\n" .. string.rep("x = 1; ", 150000) .. "\n```" },
    { "1 MB of punctuation in a python fence", "```python\n" .. string.rep(".;(", 350000) .. "\n```" },
    { "10,000 headings", string.rep("# heading\n\n", 10000) },
    { "20,000 inline math spans", string.rep("$x_i^2$ ", 20000) },
    { "5,000 code blocks", string.rep("```lua\nlocal x = 1\n```\n\n", 5000) },
    { "a 100 KB HTML block", "<div>\n" .. string.rep("<span>x</span>", 7000) .. "\n</div>" },
}

for _, reply in ipairs(replies) do
    torture(reply[1], function()
        show(reply[2])
    end)
end
