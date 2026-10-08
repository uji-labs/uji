local app = require("uji.core.app")
local Confirm = require("uji.core.ui.views.confirm")
local Pick = require("uji.core.ui.views.pick")
local Prompt = require("uji.core.ui.views.prompt")
local screen = require("support.ui")
local Select = require("uji.core.ui.views.select")
local sys = require("uji.sys")
local ui = require("uji.core.ui")

local CURSOR = "\226\150\136"
local MASK = "\226\128\162"

local function has(text, part)
    return text:find(part, 1, true) ~= nil
end

local function any(rows, part)
    for _, row in ipairs(rows) do
        if has(row, part) then
            return true
        end
    end
    return false
end

local function split(text, width)
    local rows, row, count = {}, {}, 0
    for char in text:gmatch(require("ito").text.CHAR) do
        row[#row + 1] = char
        count = count + 1
        if count == width then
            rows[#rows + 1] = table.concat(row)
            row, count = {}, 0
        end
    end
    return rows
end

local function trimmed(rows)
    local out = {}
    for index, row in ipairs(rows) do
        out[index] = row:gsub("%s+$", "")
    end
    return out
end

local function copied_to()
    local copied = {}
    sys.clipboard.set = function(value)
        copied.value = value
        return true
    end
    return copied
end

describe("the screen", function()
    it("draws the draft with the cursor in it", { size = { 40, 8 } }, function()
        screen.typing("hello")
        screen.press("left")
        screen.press("left")
        assert.is_true(has(screen.screen(), "hel" .. CURSOR .. "lo"), "the draft and its cursor should be on screen")
    end)

    it("shows no characters in a hidden prompt", { size = { 40, 10 } }, function()
        ui:present(Prompt({ title = "api key", value = "", hidden = true }))
        screen.typing("hunter2")
        screen.press("left")
        local text = screen.screen()
        assert.is_true(has(text, "api key"), "the title should be drawn")
        assert.is_true(has(text, MASK), "the value should be masked")
        assert.is_false(has(text, "hunter2"))
        assert.is_false(has(text, "2"))
        assert.is_true(has(text, CURSOR), "the cursor should still be drawn")
    end)

    it("draws the items and the query of a select", { size = { 40, 12 } }, function()
        ui:present(Select({ title = "pick one", items = { "alpha", "beta" } }))
        screen.typing("al")
        local text = screen.screen()
        assert.is_true(has(text, "pick one"), "title missing")
        assert.is_true(has(text, "alpha"), "the matching item is missing")
        assert.is_false(has(text, "beta"), "a filtered item is still drawn")
        assert.is_true(has(text, "al" .. CURSOR), "the query and cursor are missing")
    end)

    it("draws the counts and the preview of a picker", { size = { 60, 20 } }, function()
        ui:present(Pick({ title = "files", items = { "one", "two" } }))
        screen.typing("on")
        ui.modal.preview = { "a preview line" }
        ui.modal.previewed = ui.modal:chosen()
        local text = screen.screen()
        assert.is_true(has(text, "files"), "title missing")
        assert.is_true(has(text, "1/2"), "the match counts are missing")
        assert.is_true(has(text, "a preview line"), "the preview is missing")
    end)

    it("wraps a long message to the width", { size = { 30, 20 } }, function()
        app.session:append({ type = "user", text = string.rep("wrap ", 40) })
        local wrapped = 0
        for _, row in ipairs(split(screen.screen(), 30)) do
            if has(row, "wrap") then
                wrapped = wrapped + 1
            end
            assert.is_true(uji.width(row) <= 30, "a row should never run past the width")
        end
        assert.is_true(wrapped > 1, "a long message should take more than one row")
    end)

    it("lines up the columns of a table and wraps its last column", { size = { 34, 14 } }, function()
        app.session:append({
            type = "assistant",
            text = "| name | value |\n|---|---|\n| a | 1 |\n| longer | some words that wrap past the edge |",
        })
        local rows = screen.rows(true)
        local columns, wrapped = {}, false
        for _, row in ipairs(rows) do
            local at = row:find("│", 1, true)
            if at and (has(row, "name") or has(row, " a ") or has(row, "longer")) then
                columns[#columns + 1] = at
            elseif at and has(row, "past") then
                wrapped = true
            end
        end
        assert.equal(3, #columns)
        assert.equal(columns[1], columns[2])
        assert.equal(columns[1], columns[3])
        assert.is_true(wrapped, "the last column wraps under itself")
    end)

    it("keeps every column of a table wider than the screen", { size = { 40, 14 } }, function()
        app.session:append({
            type = "assistant",
            text = "| opt | description | example |\n|---|---|---|\n| a | this description is far too long to fit on one row of a forty column screen | yes |\n| b | short | no |",
        })
        local shown = table.concat(screen.rows(true), "\n")
        assert.is_true(has(shown, "example"))
        assert.is_true(has(shown, "yes"))
        assert.is_true(has(shown, "no"))
        assert.is_true(has(shown, "column screen"))
    end)

    it("keeps the choices of a tall confirm on screen and scrolls its body", { size = { 60, 20 } }, function()
        local body = {}
        for n = 1, 200 do
            body[n] = "content line " .. n
        end
        ui:present(Confirm({ title = "Write big.txt?", body = table.concat(body, "\n") }))
        local top = screen.screen()
        assert.is_true(has(top, "content line 1 "))
        assert.is_true(has(top, "of 200, scroll for more"))
        assert.is_true(has(top, "1. Yes, proceed"))
        assert.is_true(has(top, "2. No, and tell uji"))
        screen.press("end")
        local bottom = screen.screen()
        assert.is_true(has(bottom, "content line 200"))
        assert.is_false(has(bottom, "content line 1 "))
        assert.is_true(has(bottom, "1. Yes, proceed"))
    end)

    it("leaves the transcript in place when it copies a selection", { size = { 40, 12 } }, function()
        local copied = copied_to()
        for index = 1, 30 do
            app.session:append({ type = "user", text = "line " .. index })
        end
        local before = screen.rows(true)
        local row = screen.find("line 29")
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        screen.rows(true)
        ui:mouse({ kind = "drag", button = "left", row = row, col = 8 })
        screen.rows(true)
        ui:mouse({ kind = "up", button = "left", row = row, col = 8 })
        local flashed = screen.rows(true)
        assert.equal("line 29", copied.value)
        assert.is_true(has(flashed[1], "copied 1 line(s)"))
        assert.same({ unpack(before, 2) }, { unpack(flashed, 2) }, "the copy message does not push the transcript up")
        sys.sleep(1.2)
        assert.same(before, screen.rows(true), "the copy message goes away")
    end)

    it("keeps a selection on its text when the transcript moves", { size = { 40, 24 } }, function()
        local copied = copied_to()
        for index = 1, 30 do
            app.session:append({ type = "user", text = "line " .. index })
        end
        local function find(label)
            for row, line in ipairs(screen.rows(true)) do
                if line:find(label .. "$") or line:find(label .. " ") then
                    return row - 1
                end
            end
        end
        local row = find("line 28")
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        screen.rows(true)
        ui:mouse({ kind = "drag", button = "left", row = row, col = 3 })
        screen.rows(true)
        app.session:append({ type = "user", text = "line 31" })
        app.session:append({ type = "user", text = "line 32" })
        local moved = find("line 28")
        assert.are_not.equal(row, moved, "the new messages move the transcript up")
        ui:mouse({ kind = "drag", button = "left", row = moved, col = 8 })
        screen.rows(true)
        ui:mouse({ kind = "up", button = "left", row = moved, col = 8 })
        assert.equal("line 28", copied.value, "the selection follows its text as the transcript moves")
        copied.value = nil
        row = find("line 30")
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        screen.rows(true)
        ui:mouse({ kind = "drag", button = "left", row = row, col = 8 })
        ui.theme.revision = ui.theme.revision + 1
        screen.rows(true)
        ui:mouse({ kind = "up", button = "left", row = row, col = 8 })
        assert.is_nil(copied.value, "redrawing the whole transcript drops the selection")
    end)

    it("does not move a transcript scrolled up for new output", { size = { 40, 16 } }, function()
        for index = 1, 30 do
            app.session:append({ type = "user", text = "old " .. index })
        end
        local function rows()
            return trimmed(screen.rows(true))
        end
        local at_bottom = rows()
        assert.is_true(any(at_bottom, "old 30"))
        assert.is_false(any(at_bottom, "Jump to bottom"))
        ui:mouse({ kind = "scroll_up" })
        ui:mouse({ kind = "scroll_up" })
        local scrolled = rows()
        assert.are_not.equal(at_bottom[1], scrolled[1])
        assert.is_true(any(scrolled, "Jump to bottom"))
        ui.theme.revision = ui.theme.revision + 1
        assert.same(scrolled, rows(), "redrawing everything keeps the view where it was")
        local reply = {}
        for index = 1, 20 do
            reply[index] = "new " .. index
            ui:delta({ text = reply[index] .. "\n\n" })
            ui.stream:reveal_all()
            rows()
        end
        assert.same(scrolled, rows(), "a reply streaming in keeps the view where it was")
        ui:clear_stream()
        rows()
        app.session:append({ type = "assistant", text = table.concat(reply, "\n\n") })
        local finished = rows()
        assert.same(scrolled, finished, "the finished reply keeps the view where it was")
        assert.is_true(any(finished, "Jump to bottom"))
        local jump = screen.find("Jump to bottom")
        ui:mouse({ kind = "down", button = "left", row = jump, col = 20 })
        ui:mouse({ kind = "up", button = "left", row = jump, col = 20 })
        local followed = rows()
        assert.is_true(any(followed, "new 20"))
        assert.is_false(any(followed, "Jump to bottom"))
    end)

    it("opens hidden output on a click and folds it on the next", { size = { 40, 16 } }, function()
        local copied = copied_to()
        for index = 1, 30 do
            app.session:append({ type = "user", text = "old " .. index })
        end
        local output = {}
        for index = 1, 12 do
            output[index] = "out " .. index
        end
        app.session:append({ type = "shell", command = "seq 12", output = table.concat(output, "\n"), code = 0 })
        local function rows()
            return trimmed(screen.rows(true))
        end
        local function click(label, from, to)
            local row = screen.find(label)
            ui:mouse({ kind = "down", button = "left", row = row, col = from })
            if to then
                ui:mouse({ kind = "drag", button = "left", row = row, col = to })
            end
            ui:mouse({ kind = "up", button = "left", row = row, col = to or from })
        end
        local folded = rows()
        local top = screen.find("out 1")
        assert.is_true(any(folded, "out 8"))
        assert.is_false(any(folded, "out 9"))
        assert.is_true(any(folded, "… +4 lines"))
        click("… +4 lines", 8)
        local opened = rows()
        assert.equal(top, screen.find("out 1"), "the opened output stays where it was clicked")
        assert.is_false(any(opened, "+4 lines"))
        assert.is_true(any(opened, "Jump to bottom"))
        click("out 3", 5, 10)
        assert.equal("out 3", copied.value, "a drag selects instead of folding")
        assert.same({ unpack(opened, 2) }, { unpack(rows(), 2) })
        click("out 9", 7)
        assert.same({ unpack(folded, 2) }, { unpack(rows(), 2) }, "a second click folds it back and follows the bottom")
    end)

    it("draws the view a render_message handler returns", { size = { 30, 6 } }, function()
        uji.on("render_message", function(block)
            if block.type == "user" then
                local ito = require("ito")
                local styles = ito.theme().styles
                return ito.Lines({ { { "said ", styles.muted }, { block.text, styles.accent } } })
            end
        end)
        app.session:append({ type = "user", text = "hello" })
        local row = screen.find("said hello")
        assert.is_not_nil(row)
        assert.same({ "bold" }, ui.screen:spans(row)[2].modifiers)
    end)

    it("uses the picker a plugin puts in place for core commands", { size = { 40, 10 } }, function()
        local asked
        uji.model.use({ provider = "anthropic", model = "claude-sonnet-5" })
        local effort = uji.model.current().effort
        uji.ui.select = function(opts)
            asked = opts
            return "high"
        end
        require("uji.core.command").run("effort")
        assert.equal("Reasoning effort", asked.title)
        assert.equal(effort, asked.current)
        assert.equal("high", require("uji.core.model").setting("llm.effort"))
    end)

    it("switches to a model of a provider with a key from the models command", { size = { 40, 10 } }, function()
        uji.auth.save_key("groq", "test-key")
        local want
        for _, provider in ipairs(uji.provider.list()) do
            if provider.id == "groq" then
                want = provider.models[2].id
            end
        end
        uji.model.use({ provider = "anthropic", model = "claude-sonnet-5" })
        local marked
        uji.ui.select = function(opts)
            marked = opts.current
            for _, item in ipairs(opts.items) do
                if item:sub(-#want) == want then
                    return item
                end
            end
        end
        require("uji.core.command").run("models")
        assert.equal("claude-sonnet-5", marked:match("[^ ]+$"))
        local current = uji.model.current()
        assert.equal("groq", current.provider)
        assert.equal(want, current.model)
        assert.is_true(uji.auth.authenticated("groq"))
    end)

    it("replaces a built in command when a plugin adds its name", { size = { 40, 10 } }, function()
        local ran = false
        uji.command.add("help", function()
            ran = true
        end)
        require("uji.core.command").run("help")
        assert.is_true(ran)
        local listed = {}
        for _, name in ipairs(uji.command.list()) do
            listed[name] = true
        end
        assert.is_true(listed.help and listed.login)
    end)
end)
