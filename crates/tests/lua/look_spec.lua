local app = require("uji.core.app")
local Confirm = require("uji.core.ui.views.confirm")
local event = require("uji.core.event")
local fixture = require("support.fixture")
local Pick = require("uji.core.ui.views.pick")
local plugin = require("uji.core.plugin")
local Prompt = require("uji.core.ui.views.prompt")
local sandbox = require("support.sandbox")
local sessions = require("uji.core.ui.sessions")
local screen = require("support.ui")
local Select = require("uji.core.ui.views.select")
local Suggest = require("uji.core.ui.views.suggest")
local sys = require("uji.sys")
local text = require("ito").text
local ui = require("uji.core.ui")

local GOLDEN = sandbox.fixtures .. "/look/"

local function styled(run)
    local parts = {}
    if run.fg then
        parts[#parts + 1] = "fg=" .. run.fg
    end
    if run.bg then
        parts[#parts + 1] = "bg=" .. run.bg
    end
    for _, modifier in ipairs(run.modifiers) do
        parts[#parts + 1] = modifier
    end
    return table.concat(parts, " ")
end

local function capture(draw)
    ui.screen:clear()
    if draw then
        draw()
    else
        ui:paint()
    end
    local _, height = ui.screen:size()
    local out = {}
    for row = 0, height - 1 do
        out[#out + 1] = string.format("%2d|%s", row, (ui.screen:text(row):gsub("%s+$", "")))
        local col, marks = 0, {}
        for _, run in ipairs(ui.screen:spans(row)) do
            local size = text.width(run.text)
            local style = styled(run)
            if style ~= "" then
                marks[#marks + 1] = col .. "+" .. size .. " " .. style
            end
            col = col + size
        end
        if #marks > 0 then
            out[#out + 1] = "  |" .. table.concat(marks, "; ")
        end
    end
    return table.concat(out, "\n") .. "\n"
end

local function differ(want, got)
    local wanted, gotten = {}, {}
    for line in want:gmatch("[^\n]*") do
        wanted[#wanted + 1] = line
    end
    for line in got:gmatch("[^\n]*") do
        gotten[#gotten + 1] = line
    end
    for index = 1, math.max(#wanted, #gotten) do
        if wanted[index] ~= gotten[index] then
            return index, wanted[index] or "", gotten[index] or ""
        end
    end
end

local function look(name, draw)
    local path = GOLDEN .. name .. ".txt"
    local got = capture(draw)
    if sys.os.env("UJI_BLESS") then
        sandbox.write(path, got)
        return
    end
    local want = sys.fs.read(path)
    assert(want, "no golden screen " .. name .. "; run the tests with UJI_BLESS=1 to write it")
    if got ~= want then
        local kept = sandbox.root .. "/" .. name .. ".txt"
        sandbox.write(kept, got)
        local line, expected, actual = differ(want, got)
        error(string.format("%s differs at line %d\nwant: %s\n got: %s\nthe whole screen is in %s", name, line, expected, actual, kept), 0)
    end
end

local function click(label)
    local row = screen.find(label)
    ui:mouse({ kind = "down", button = "left", row = row, col = 6 })
    ui:mouse({ kind = "up", button = "left", row = row, col = 6 })
end

describe("the default look", function()
    before_each(function()
        assert(pcall(plugin.run, "defaults", nil, require, "uji.builtin.defaults"))
    end)

    it("draws every kind of message", { size = { 80, 70 } }, function()
        fixture.messages()
        look("messages")
    end)

    it("draws markdown and a reply as it streams", { size = { 80, 60 } }, function()
        fixture.markdown()
        look("markdown")
    end)

    it("draws thinking when it is shown", { size = { 80, 20 } }, function()
        uji.ui.configure({ show_thinking = true })
        app.session:append({ type = "user", text = "Think about it" })
        app.session:append({ type = "assistant", text = "Done thinking.", reasoning = "First this, then that." })
        ui:delta({ kind = "reasoning", text = "Still pondering" })
        look("thinking")
    end)

    it("opens and folds tool output on a click", { size = { 80, 30 } }, function()
        app.session:append({ type = "shell", command = "seq 12", output = fixture.numbered("out", 12), code = 0 })
        look("folded")
        click("… +4 lines")
        look("expanded")
    end)

    it("draws an edit as a diff and a read as its summary", { size = { 80, 16 } }, function()
        local before = 'def main():\n    name = "world"\n    print("Hello, " + name)\n    return 0\n'
        local after = 'def main():\n    name = "world"\n    print("Hi, " + name)\n    print("bye")\n    return 0\n'
        local edit = '{"path":"greet.py","old_string":"x","new_string":"y"}'
        app.session:append({ type = "assistant", text = "", tool_calls = { { id = "a", name = "edit_file", arguments = edit } } })
        app.session:append({
            type = "tool",
            tool_call_id = "a",
            name = "edit_file",
            content = "edited greet.py at line 3",
            diff = uji.diff(before, after, "greet.py"),
        })
        app.session:append({
            type = "assistant",
            text = "",
            tool_calls = { { id = "b", name = "read_file", arguments = '{"path":"greet.py"}' } },
        })
        app.session:append({ type = "tool", tool_call_id = "b", name = "read_file", content = after, summary = "Read 5 lines" })
        look("diff")
    end)

    it("shows the jump to the bottom when scrolled up", { size = { 80, 16 } }, function()
        for index = 1, 30 do
            app.session:append({ type = "user", text = "line " .. index })
        end
        screen.rows(true)
        ui:mouse({ kind = "scroll_up" })
        ui:mouse({ kind = "scroll_up" })
        look("jump")
    end)

    it("highlights a selection", { size = { 80, 12 } }, function()
        app.session:append({ type = "user", text = "select some of this text" })
        local row = screen.find("select some")
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        ui:mouse({ kind = "drag", button = "left", row = row, col = 12 })
        look("selection")
    end)

    it("draws the draft with its cursor", { size = { 80, 12 } }, function()
        ui:set_input("first line of the draft\nsecond line")
        screen.press("left")
        screen.press("left")
        look("input")
    end)

    it("draws the waiting line while working", { size = { 80, 12 } }, function()
        app.agent.working = function()
            return true
        end
        app.agent.elapsed = function()
            return 3.4
        end
        event.emit("status_changed", {})
        look("activity")
    end)

    it("draws a flash message", { size = { 80, 8 } }, function()
        ui:flash("copied 1 line(s)")
        look("flash")
    end)

    it("draws a select", { size = { 80, 24 } }, function()
        local items = {}
        for index = 1, 15 do
            items[index] = "model-" .. index
        end
        ui:present(Select({ title = "Pick a model", items = items }))
        screen.press("down")
        look("select")
    end)

    it("draws a picker with its preview", { size = { 100, 24 } }, function()
        ui:present(Pick({
            title = "Files",
            items = { "src/main.lua", "src/ui.lua", "README.md" },
            preview = function(item)
                return { "preview of " .. item, "second line" }
            end,
        }))
        ui:paint()
        sys.sleep(0.01)
        look("pick")
    end)

    it("draws a prompt in the clear and hidden", { size = { 80, 10 } }, function()
        local prompt = ui:present(Prompt({ title = "Your name", value = "Ada" }))
        look("prompt")
        prompt:close()
        ui:present(Prompt({ title = "API key", value = "secret", hidden = true }))
        look("prompt-hidden")
    end)

    it("draws an approval", { size = { 80, 20 } }, function()
        ui:present(Confirm({ title = "Allow tool call?", body = "run_command: ls -la\nin the project directory" }))
        look("confirm")
    end)

    it("draws the sessions picker", { size = { 80, 12 } }, function()
        local now = sys.os.now()
        local listed = {}
        for index = 1, 12 do
            listed[index] = {
                title = "session " .. index,
                updated = now - index * 3600 * 1000,
                id = string.format("00000000-0000-0000-0000-%012d", index),
            }
        end
        local picker = sessions.Sessions(listed, "/work/project")
        picker:key({ key = "down" })
        look("sessions", function()
            picker:draw()
        end)
        local empty = sessions.Sessions({}, "/work/project")
        look("sessions-empty", function()
            empty:draw()
        end)
    end)

    it("draws command suggestions", { size = { 80, 12 } }, function()
        ui:present(Suggest({
            { name = "model", desc = "pick a model" },
            { name = "effort", desc = "set the reasoning effort" },
            { name = "compact", desc = "summarise the session" },
        }))
        screen.press("down")
        look("suggest")
    end)
end)
