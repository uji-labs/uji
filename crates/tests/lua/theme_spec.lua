local app = require("uji.core.app")
local default = require("uji.themes.default")
local Confirm = require("uji.core.ui.views.confirm")
local ito = require("ito")
local fixture = require("support.fixture")
local model = require("uji.core.model")
local plugin = require("uji.core.plugin")
local sandbox = require("support.sandbox")
local screen = require("support.ui")
local Pick = require("uji.core.ui.views.pick")
local Prompt = require("uji.core.ui.views.prompt")
local Select = require("uji.core.ui.views.select")
local sessions = require("uji.core.ui.sessions")
local Suggest = require("uji.core.ui.views.suggest")
local ui = require("uji.core.ui")

local DEFAULT_COLOURS = { "#D4D4D4", "#808080", "#E0AF68", "Cyan", "#343541", "#3A3A4A", "White", "Red" }

local PROBE = default({
    name = "probe",
    colors = {
        text = ito.rgb(0x101010),
        muted = ito.rgb(0x202020),
        code = ito.rgb(0x303030),
        accent = ito.rgb(0x404040),
        user_bg = ito.rgb(0x505050),
        selected_bg = ito.rgb(0x606060),
        cursor = ito.rgb(0x707070),
        error = ito.rgb(0x909090),
        notice = ito.rgb(0xa0a0a0),
    },
    symbols = {
        spinner = { "P" },
        tool = "T>",
        branch = "B>",
        more = "M>",
        shell = "S>",
        rule = "=",
        notice = "N>",
        thinking = "H>",
        queued = "Q>",
        running = "R>",
        jump = "J>",
        bullets = { "B1", "B2", "B3" },
        quote = "Q|",
        column = "C|",
        task_done = "[D]",
        task_open = "[O]",
        cursor = "C",
        mask = "*",
        pointer = "P>",
        prompt = "?",
    },
    borders = {
        plain = {
            top_left = "1",
            top_right = "2",
            bottom_left = "3",
            bottom_right = "4",
            horizontal = "=",
            vertical = "|",
        },
        rounded = {
            top_left = "5",
            top_right = "6",
            bottom_left = "7",
            bottom_right = "8",
            horizontal = "~",
            vertical = "!",
        },
    },
    text = {
        confirm_yes = "Ja",
        confirm_no = "Nein",
        called = "Invoked",
        exit = "status",
        compacted = "squashed",
        hidden = "%d more",
        jump = "Latest",
        ordered = "%d)",
        current = "(now)",
        range = "%d to %d / %d",
        confirm_allow = "go",
        confirm_deny = "stop",
        scroll = "%d..%d of %d",
        sessions_title = "Past %s",
        sessions_empty = "Nothing here",
        column_title = "NAME",
        column_updated = "WHEN",
        column_id = "KEY",
        key_move = "up/down",
        key_open = "ret",
        key_quit = "q",
        navigate = "move",
        resume = "open",
        quit = "leave",
    },
    limits = {
        spinner_interval = 0.5,
        suggest_rows = 2,
        tool_preview = 3,
        argument_preview = 5,
        message_gap = 0,
        section_gap = 2,
        bottom_gap = 2,
        indent = 3,
        rule_width = 10,
        block_gap = 0,
        reply_margin = 2,
        input_rows = 3,
        select_rows = 4,
        suggest_name = 8,
        preview_min = 10,
        sessions_updated = 10,
        sessions_id = 20,
    },
    views = {
        [uji.ui.Screen] = function(slots)
            local ctx = ito.theme()
            return ito.VStack({
                slots.composer():border(ctx.borders.plain),
                slots.transcript():grow(),
                slots.modals(),
            })
        end,
    },
})

local function has(value, part)
    return tostring(value):find(part, 1, true) ~= nil
end

local function colours(found)
    for _, run in ipairs(screen.runs()) do
        if run.fg then
            found[run.fg] = true
        end
        if run.bg then
            found[run.bg] = true
        end
    end
    return found
end

local TRANSCRIPT_ROW = 4

local function transcript_rows()
    return { unpack(screen.rows(true), TRANSCRIPT_ROW) }
end

local function theme_file(name, source)
    sandbox.write(sandbox.cfg .. "/lua/uji/themes/" .. name .. ".lua", source)
end

local function suggestions()
    return {
        { name = "model", desc = "pick a model" },
        { name = "effort", desc = "set the reasoning effort" },
        { name = "compact", desc = "summarise the session" },
    }
end

describe("themes", function()
    before_each(function()
        assert(pcall(plugin.run, "defaults", nil, require, "uji.builtin.defaults"))
    end)

    it("recolours everything uji draws", { size = { 80, 70 } }, function()
        uji.ui.configure({ theme = PROBE })
        fixture.messages()
        local found = colours({})
        fixture.markdown()
        colours(found)
        ui:set_input("a draft")
        colours(found)
        local row = screen.find("a notice")
        ui:mouse({ kind = "down", button = "left", row = row, col = 1 })
        ui:mouse({ kind = "drag", button = "left", row = row, col = 5 })
        ui:flash("copied")
        colours(found)
        ui:present(Select({ title = "Pick", items = { "a", "b", "c" } }))
        colours(found)
        ui.modal:close()
        ui:present(Confirm({ title = "Allow?", body = "run it" }))
        colours(found)
        ui.modal:close()
        ui:present(Suggest(suggestions()))
        colours(found)
        for _, colour in ipairs(DEFAULT_COLOURS) do
            assert.is_nil(found[colour], colour .. " is a default colour the theme replaced")
        end
        for _, colour in ipairs({ "#101010", "#202020", "#303030", "#404040", "#505050", "#606060" }) do
            assert.is_true(found[colour], colour .. " from the theme is on the screen")
        end
    end)

    it("changes the symbols, words and sizes uji uses", { size = { 80, 20 } }, function()
        uji.ui.configure({ theme = PROBE })
        app.agent.elapsed = function()
            return 3.4
        end
        assert.equal("P", ui:loader_frame())
        ui:present(Confirm({ title = "Allow?", body = "run it" }))
        local approval = screen.screen()
        assert.is_true(has(approval, "1. Ja, go (y)"))
        assert.is_true(has(approval, "2. Nein, stop (esc)"))
        ui.modal:close()
        ui:present(Suggest(suggestions()))
        local listed = screen.screen()
        assert.is_true(has(listed, "model"))
        assert.is_true(has(listed, "effort"))
        assert.is_false(has(listed, "compact"))
    end)

    it("lays the screen out the way the theme says", { size = { 40, 10 } }, function()
        uji.ui.configure({ theme = PROBE })
        app.session:append({ type = "user", text = "hello" })
        local rows = screen.rows(true)
        assert.equal("1" .. string.rep("=", 38) .. "2", rows[1])
        assert.equal("|C", rows[2]:sub(1, 2))
        assert.is_true(has(rows[5], "hello"))
        assert.is_false(has(rows[10], "─"))
    end)

    it("sizes rows and columns by cells, shares and content", { size = { 40, 10 } }, function()
        uji.ui.configure({
            theme = default({
                views = {
                    [uji.ui.Screen] = function(slots)
                        local ctx = ito.theme()
                        local function label(value)
                            return ito.Lines({ { { value, ctx.styles.text } } })
                        end
                        return ito.VStack({
                            ito.HStack({
                                label("A"):share(0.25),
                                label("B"):width(5),
                                label("C"):grow(),
                                label("D"):grow(),
                            }):height(1),
                            slots.transcript():grow(),
                            label("E"),
                            slots.composer(),
                        })
                    end,
                },
            }),
        })
        local rows = screen.rows(true)
        assert.equal("A         B    C           D", rows[1]:gsub("%s+$", ""))
        assert.equal("E", rows[9]:gsub("%s+$", ""))
        assert.equal("█", rows[10]:gsub("%s+$", ""))
    end)

    it("puts toolbar items in the sections the screen shows, in the order they were declared", { size = { 40, 10 } }, function()
        local placement = ito.ToolbarPlacement
        local function text(value)
            return function()
                return ito.Text(value)
            end
        end
        uji.ui.toolbar({
            ito.ToolbarItem(placement.top_bar_leading, text("banner")),
            ito.ToolbarItem(placement.top_bar_trailing, text("tag")),
        })
        local first = uji.ui.toolbar({ ito.ToolbarItem(placement.bottom_bar, text("first")) })
        uji.ui.toolbar({
            ito.ToolbarItem(placement.bottom_bar, text("second")),
            ito.ToolbarItem(placement.bottom_bar, function()
                error("no badge today", 0)
            end),
        })
        local rows = screen.rows(true)
        assert.equal("banner" .. string.rep(" ", 31) .. "tag", rows[1])
        assert.equal(string.rep("─", 40), rows[6])
        assert.equal("█", rows[7]:gsub("%s+$", ""))
        assert.equal(string.rep("─", 40), rows[8])
        assert.equal("first", rows[9]:gsub("%s+$", ""))
        assert.equal("second", rows[10]:gsub("%s+$", ""))
        screen.rows(true)
        ui:take_notices()
        local raised = 0
        for _, notice in ipairs(ui.notices) do
            raised = raised + (has(notice, "toolbar item: no badge today") and 1 or 0)
        end
        assert.equal(1, raised)
        assert.is_true(first:remove())
        assert.is_false(first:remove())
        assert.equal("second", (screen.rows(true)[10]:gsub("%s+$", "")))
        uji.ui.configure({
            theme = default({
                views = {
                    [uji.ui.Screen] = function(slots)
                        return ito.VStack({ slots.transcript():grow(), slots.composer() })
                    end,
                },
            }),
        })
        screen.rows(true)
        screen.rows(true)
        ui:take_notices()
        local missing = 0
        for _, notice in ipairs(ui.notices) do
            missing = missing + (has(notice, "toolbar: nothing shows the items placed at bottom_bar") and 1 or 0)
        end
        assert.equal(1, missing)
        assert.has_error(function()
            uji.ui.toolbar("x")
        end, "uji.ui.toolbar takes a list of ito.ToolbarItem")
    end)

    it("falls back to the default screen when the theme's breaks", { size = { 40, 10 } }, function()
        local cases = {
            {
                function()
                    return { "a table" }
                end,
                "a view must give a view, not a table",
            },
            {
                function(slots)
                    return ito.VStack({ slots.composer():align("up") })
                end,
                "align takes one of ito.Alignment",
            },
            {
                function(slots)
                    return ito.VStack({ slots.composer():grow(0) })
                end,
                "grow takes a weight above 0, not 0",
            },
            {
                function(slots)
                    return ito.VStack({ slots.composer():share(2) })
                end,
                "share takes a fraction from 0 to 1, not 2",
            },
            {
                function()
                    return ito.VStack({ ito.Text(5) })
                end,
                "Text takes a string, not a number",
            },
            {
                function(slots)
                    return ito.VStack({ slots.composer():border({}) })
                end,
                "a border needs top_left",
            },
        }
        for _, case in ipairs(cases) do
            uji.ui.configure({ theme = default({ views = { [uji.ui.Screen] = case[1] } }) })
            local rows = screen.rows(true)
            ui:take_notices()
            local said = tostring(ui.notices[#ui.notices])
            assert.is_true(has(said, case[2]), said)
            assert.equal(string.rep("─", 40), rows[#rows - 2])
        end
        local count = #ui.notices
        screen.rows(true)
        ui:take_notices()
        assert.equal(count, #ui.notices, "the same problem is reported once")
    end)

    it("floats a picker when the screen has no place for pickers", { size = { 40, 12 } }, function()
        uji.ui.configure({
            theme = default({
                views = {
                    [uji.ui.Screen] = function(slots)
                        return ito.VStack({ slots.transcript():grow(), slots.composer() })
                    end,
                },
            }),
        })
        ui:present(Select({ title = "Pick one", items = { "a", "b" } }))
        local rows = screen.rows(true)
        assert.equal("    Pick one", (rows[3]:gsub("%s+$", "")))
        assert.equal("  › a", (rows[6]:gsub("%s+$", "")))
    end)

    it("draws an approval in a composer that sits in a row", { size = { 40, 12 } }, function()
        uji.ui.configure({
            theme = default({
                views = {
                    [uji.ui.Screen] = function(slots)
                        return ito.VStack({
                            slots.transcript():grow(),
                            slots.modals(),
                            ito.HStack({ ito.Text("> "), slots.composer() }),
                        })
                    end,
                },
            }),
        })
        ui:present(Confirm({ title = "Allow?", body = "run it" }))
        local rows = screen.rows(true)
        ui:take_notices()
        assert.is_true(has(table.concat(rows, "\n"), "1. Yes, proceed (y)"))
        assert.same({}, ui.notices)
    end)

    it("clears the room of a picker drawn over the transcript", { size = { 40, 12 } }, function()
        uji.ui.configure({
            theme = default({
                views = {
                    [uji.ui.Screen] = function(slots)
                        return ito.VStack({
                            ito.ZStack({
                                slots.transcript():grow(),
                                slots.modals():align(ito.Alignment.bottom),
                            }):grow(),
                            slots.composer(),
                        })
                    end,
                },
            }),
        })
        for index = 1, 12 do
            app.session:append({ type = "user", text = string.rep("x", 30) .. index })
        end
        ui:present(Select({ title = "Pick one", items = { "a", "b" } }))
        local rows = screen.rows(true)
        local title = screen.find("Pick one") + 1
        assert.equal("", (rows[title - 1]:gsub("%s+$", "")))
        assert.equal("", (rows[title + 1]:gsub("%s+$", "")))
    end)

    it("draws the transcript with the theme's symbols, words and spacing", { size = { 80, 70 } }, function()
        uji.ui.configure({ theme = PROBE, show_thinking = true })
        fixture.messages()
        app.session:append({ type = "assistant", text = "Done.", reasoning = "a thought" })
        local rows = transcript_rows()
        local all = table.concat(rows, "\n")
        for _, gone in ipairs({ "•", "└", "…", "⋯", "›", "│", "!", "Called", "exit", "compacted", "lines" }) do
            assert.is_false(has(all, gone), gone .. " is drawn although the theme replaced it")
        end
        for _, shown in ipairs({
            " T> Read notes.txt",
            ' T> Invoked mystery {"que',
            "   B> row 1",
            "      M> 9 more",
            " S> false  (status 1)",
            "squashed",
            " N> a notice for you",
            " Q> a queued message",
            " R> run_command  compiling the project",
            " H> a thought",
        }) do
            assert.is_true(has(all, shown), shown .. " is missing")
        end
        for index, row in ipairs(rows) do
            if has(row, "A system note") then
                assert.is_true(has(rows[index + 1], "Something went wrong"), "no gap between messages")
            end
        end
    end)

    it("draws markdown with the theme's marks and spacing", { size = { 80, 60 } }, function()
        uji.ui.configure({ theme = PROBE })
        fixture.markdown()
        local rows = transcript_rows()
        local all = table.concat(rows, "\n")
        for _, gone in ipairs({ "•", "◦", "▪", "│", "[x]", "[ ]", "1.", "──" }) do
            assert.is_false(has(all, gone), gone .. " is drawn although the theme replaced it")
        end
        for _, shown in ipairs({
            "  B1 first",
            "     B2 nested",
            "        B3 deeper",
            "  1) one",
            "  Q| a quote",
            "     Q| nested quote",
            "  B1 [D] done",
            "  B1 [O] open",
            "    name C| value",
            "  ==========",
        }) do
            assert.is_true(has(all, shown), shown .. " is missing")
        end
        for index, row in ipairs(rows) do
            if has(row, "Heading one") then
                assert.is_true(has(rows[index + 1], "Some bold"), "no gap between blocks")
            end
        end
    end)

    it("draws headings and code blocks with the views a theme gives", { size = { 60, 20 } }, function()
        uji.ui.configure({
            theme = default({
                views = {
                    [uji.ui.Heading] = function(props)
                        local hashes = string.rep("#", props.level) .. " "
                        return ito.HStack({ ito.Text(hashes):style(ito.theme().styles.muted), props.content })
                    end,
                    [uji.ui.CodeBlock] = function(props)
                        local label = "<" .. (props.language or "code") .. ">"
                        return ito.VStack({ ito.Text(label):style(ito.theme().styles.dim), ito.Lines(props.lines) })
                    end,
                },
            }),
        })
        app.session:append({ type = "assistant", text = "## Setup\n\n```lua\nlocal x = 1\n```" })
        local all = screen.screen()
        assert.is_true(has(all, " ## Setup"))
        assert.is_true(has(all, " <lua>"))
        assert.is_true(has(all, " local x = 1"))
    end)

    it("draws pickers, prompts and the approval with the theme's marks, words and sizes", { size = { 80, 24 } }, function()
        uji.ui.configure({ theme = PROBE })
        local seen = {}
        local function look()
            seen[#seen + 1] = table.concat(screen.rows(true), "\n")
            return seen[#seen]
        end
        local items = {}
        for index = 1, 6 do
            items[index] = "item-" .. index
        end
        ui:present(Select({ title = "Pick one", items = items }))
        local select = look()
        assert.is_true(has(select, "  ? C"))
        assert.is_true(has(select, "P> item-1"))
        assert.is_true(has(select, "item-4"))
        assert.is_false(has(select, "item-5"))
        assert.is_true(has(select, "1 to 4 / 6"))
        ui.modal:close()
        ui:present(Prompt({ title = "Key", value = "secret", hidden = true }))
        assert.is_true(has(look(), "  ? ******C"))
        ui.modal:close()
        local body = {}
        for index = 1, 30 do
            body[index] = "detail " .. index
        end
        ui:present(Confirm({ title = "Allow?", body = table.concat(body, "\n") }))
        local approval = look()
        assert.is_true(has(approval, "P> 1. Ja, go (y)"))
        assert.is_true(has(approval, "2. Nein, stop (esc)"))
        assert.is_true(has(approval, "1.."))
        ui.modal:close()
        ui:present(Suggest(suggestions()))
        assert.is_true(has(look(), "  model   pick a model"))
        ui.modal:close()
        ui:present(Pick({ title = "Files", items = { "a.lua", "b.lua" } }))
        local pick = look()
        assert.is_true(has(pick, "1 Files ="))
        assert.is_true(has(pick, "|? a.lua"))
        assert.is_true(has(pick, "|? C   2/2"))
        ui.modal:close()
        ui:present(Select({ title = "Done", items = { "x" } }))
        ui.modal:close()
        ui:set_input("one\ntwo\nthree\nfour\nfive")
        local drafted = screen.rows(true)
        local count = 0
        for _, row in ipairs(drafted) do
            if row:match("^|") and not row:match("^|%s*|$") then
                count = count + 1
            end
        end
        assert.equal(3, count, "the draft shows input_rows rows")
        seen[#seen + 1] = table.concat(drafted, "\n")
        local all = table.concat(seen, "\n")
        for _, gone in ipairs({ "›", "█", "•", "┌", "─", "│", "(current)", "proceed", "–" }) do
            assert.is_false(has(all, gone), gone .. " is drawn although the theme replaced it")
        end
    end)

    it("puts the theme's input mark in front of each row of the input line", { size = { 20, 10 } }, function()
        uji.ui.configure({ theme = default({ symbols = { input = "» " } }) })
        ui:set_input("one two three four five six")
        local marked = {}
        for _, row in ipairs(screen.rows(true)) do
            if row:sub(1, #"» ") == "» " then
                marked[#marked + 1] = row
            end
        end
        assert.equal(2, #marked)
        assert.is_true(has(marked[1], "one two"))
        assert.is_true(has(marked[2], "six"))
    end)

    it("opens a list on its current item and labels it with the theme's word", { size = { 60, 12 } }, function()
        uji.ui.configure({ theme = PROBE })
        for _, make in ipairs({ Select, Pick }) do
            local modal = make({ title = "Pick", items = { "a", "b", "c" }, current = "b" })
            ui:present(modal)
            assert.equal("b", modal:chosen())
            local shown = table.concat(screen.rows(true), "\n")
            assert.is_true(has(shown, "b (now)"))
            assert.is_false(has(shown, "a (now)"))
            ui.modal:close()
        end
    end)

    it("draws the sessions picker with the theme's words and sizes", { size = { 80, 10 } }, function()
        uji.ui.configure({ theme = PROBE })
        local listed = { { title = "first", updated = 0, id = "abc" } }
        local function drawn()
            local _, height = ui.screen:size()
            local rows = {}
            for row = 0, height - 1 do
                rows[#rows + 1] = ui.screen:text(row)
            end
            return table.concat(rows, "\n")
        end
        sessions.Sessions(listed, "/work"):draw()
        local all = drawn()
        for _, shown in ipairs({ "1 Past /work =", "|NAME", "WHEN", "KEY", "up/down move", "ret open", "q leave" }) do
            assert.is_true(has(all, shown), shown .. " is missing")
        end
        sessions.Sessions({}, "/work"):draw()
        local empty = drawn()
        assert.is_true(has(empty, "Nothing here"))
        for _, gone in ipairs({ "TITLE", "UPDATED", "navigate", "Sessions in", "┌" }) do
            assert.is_false(has(all .. empty, gone), gone .. " is drawn although the theme replaced it")
        end
    end)

    it("shows the jump with the theme's words and keeps its gap at the bottom", { size = { 40, 12 } }, function()
        uji.ui.configure({ theme = PROBE })
        for index = 1, 30 do
            app.session:append({ type = "user", text = "line " .. index })
        end
        screen.rows(true)
        ui:mouse({ kind = "scroll_up" })
        local rows = screen.rows(true)
        local jump = screen.find("J> Latest")
        assert.is_not_nil(jump)
        assert.equal(" J> Latest ", rows[jump + 1]:match("^%s*(.-)%s*$") and rows[jump + 1]:sub(15, 25))
        ui:mouse({ kind = "down", button = "left", row = jump, col = 20 })
        ui:mouse({ kind = "up", button = "left", row = jump, col = 20 })
        screen.rows(true)
        assert.is_nil(screen.find("J> Latest"))
    end)

    it("draws a view the theme overrides, and the default for one that breaks", { size = { 60, 12 } }, function()
        uji.ui.configure({
            theme = default({
                views = {
                    [uji.ui.Notice] = function(props)
                        return ito.Lines({ { { "<<" .. props.text .. ">>", ito.theme().styles.notice } } })
                    end,
                    [uji.ui.Queued] = function()
                        error("no queue today", 0)
                    end,
                },
            }),
        })
        require("uji.core.notices").push("hello")
        ui:take_notices()
        app.agent.queue = { { text = "later" } }
        local all = screen.screen()
        assert.is_true(has(all, "<<hello>>"))
        assert.is_true(has(all, " › later"))
        ui:take_notices()
        assert.is_true(has(table.concat(ui.notices, "\n"), "theme view: no queue today"))
        local ok, err = pcall(uji.ui.configure, { theme = default({ views = { bogus = function() end } }) })
        assert.is_false(ok)
        assert.is_true(has(err, "theme default.views: keys must be views made with ito.view, not bogus"))
    end)

    it("loads a theme by name and builds it on another", { size = { 40, 8 } }, function()
        theme_file(
            "base",
            [[
local ito = require("ito")
return require("uji.themes.default")({
    name = "base",
    colors = { accent = ito.rgb(0x123456), text = ito.rgb(0x111111) },
})]]
        )
        theme_file(
            "child",
            [[
local ito = require("ito")
local base = require("uji.themes.base")
return require("uji.themes.default")({
    name = "child",
    colors = { accent = base.colors.accent, text = ito.rgb(0x654321) },
})]]
        )
        uji.ui.configure({ theme = "child" })
        local tokens = ui.theme.tokens
        assert.equal("child", tokens.name)
        assert.equal(ito.rgb(0x123456), tokens.colors.accent)
        assert.equal(ito.rgb(0x654321), tokens.colors.text)
        assert.equal(ito.rgb(0x808080), tokens.colors.muted)
        assert.equal(ito.TextStyle({ foreground = ito.rgb(0x123456), bold = true }), tokens.styles.accent)
        uji.ui.configure({
            theme = default({
                colors = { muted = ito.rgb(0x222222) },
                styles = function(colors)
                    return { user = ito.TextStyle({ foreground = colors.muted, italic = true }) }
                end,
            }),
        })
        assert.equal(ito.TextStyle({ foreground = ito.rgb(0x222222), italic = true }), ui.theme.tokens.styles.user)
        assert.equal(ito.TextStyle({ foreground = ito.rgb(0x222222) }), ui.theme.tokens.styles.muted)
    end)

    it("draws rgb and indexed colours", { size = { 40, 8 } }, function()
        uji.ui.configure({
            theme = default({
                colors = { text = ito.rgb(0xc0c0c0), muted = ito.Color.indexed(245), user_bg = ito.Color.indexed(236) },
            }),
        })
        app.session:append({ type = "user", text = "hello" })
        local found = colours({})
        assert.is_true(found["#C0C0C0"])
        assert.is_true(found["236"])
        assert.is_true(found["245"])
    end)

    it("names what is wrong with a theme and keeps the one it had", { size = { 40, 8 } }, function()
        theme_file("broken", "return 42")
        uji.ui.configure({ theme = PROBE })
        local tokens, revision = ui.theme.tokens, ui.theme.revision
        local function built(changes)
            return function()
                return default(changes)
            end
        end
        local cases = {
            { { colours = {} }, "theme.colours: a theme has name, colors, styles, symbols" },
            { { roles = {} }, "theme.roles: a theme has name, colors, styles" },
            { { palette = {} }, "theme.palette: a theme has name, colors, styles" },
            { { extends = "default" }, "theme.extends: a theme has name, colors, styles" },
            { { views = {} }, "theme.colors: must be a table, not a nil" },
            { built({ colors = { text = "#d4d4d4" } }), "a TextStyle's foreground must be an ito.Color, not a string" },
            { built({ colors = { brand = 245 } }), "theme default.colors.brand: must be an ito.Color, not a number" },
            { built({ styles = { user = { fg = "text" } } }), "theme default.styles.user: must be an ito.TextStyle, not a table" },
            { built({ symbols = { spiner = { "x" } } }), "theme default.symbols.spiner: the default theme has no symbol named spiner" },
            { built({ limits = { suggest_rows = -1 } }), "theme default.limits.suggest_rows: must be a number that is not negative" },
            { "missing", "no theme named missing" },
            { "broken", "theme broken must return a table" },
            { 42, "theme must be a theme name or a theme table" },
        }
        for _, case in ipairs(cases) do
            local ok, err = pcall(function()
                local theme = case[1]
                uji.ui.configure({ theme = type(theme) == "function" and theme() or theme })
            end)
            assert.is_false(ok, case[2])
            assert.is_true(has(err, case[2]), "expected " .. case[2] .. ", got " .. tostring(err))
            assert.equal(tokens, ui.theme.tokens)
            assert.equal(revision, ui.theme.revision)
        end
    end)

    it("draws links and code in the colours a theme adds", { size = { 40, 8 } }, function()
        local S = ito.TextStyle
        local added = { link = ito.rgb(0x010101), keyword = ito.rgb(0x020202), number = ito.rgb(0x030303), comment = ito.rgb(0x040404) }
        uji.ui.configure({ theme = default({ colors = added }) })
        local styles = ui.theme.tokens.styles
        assert.equal(S({ foreground = added.link, underline = true }), styles.link)
        assert.equal(S({ foreground = added.keyword }), styles.code_keyword)
        assert.equal(S({ foreground = added.number }), styles.code_number)
        assert.equal(S({ foreground = added.comment, italic = true }), styles.code_comment)
    end)

    it("paints the screen and the lists over it with the theme's screen style", { size = { 40, 12 } }, function()
        local function backgrounds()
            local found = {}
            for _, run in ipairs(screen.runs()) do
                found[run.bg or "none"] = true
            end
            return found
        end
        assert.same({ none = true }, backgrounds())
        uji.ui.configure({ theme = default({ colors = { background = ito.rgb(0x0a0b0c) } }) })
        assert.same({ ["#0A0B0C"] = true }, backgrounds())
        for _, modal in ipairs({ Select({ title = "Pick", items = { "a", "b" } }), Pick({ title = "Find", items = { "a", "b" } }) }) do
            ui:present(modal)
            local found = backgrounds()
            assert.is_nil(found.none)
            assert.is_true(found["#0A0B0C"])
            ui.modal:close()
        end
    end)

    it("tells which theme is in use", { size = { 40, 8 } }, function()
        uji.ui.configure({ theme = PROBE })
        assert.equal(PROBE, uji.ui.theme())
        theme_file("plain", 'return require("uji.themes.default")({ name = "plain" })')
        uji.ui.configure({ theme = "plain" })
        assert.equal("plain", uji.ui.theme())
    end)

    it("keeps a saved theme and names one that no longer loads", { size = { 40, 8 } }, function()
        theme_file("kept", 'return require("uji.themes.default")({ name = "kept" })')
        uji.ui.save_theme("kept")
        assert.equal("kept", model.setting("ui.theme"))
        assert.equal("default", uji.ui.theme())
        ui.theme:restore()
        assert.equal("kept", uji.ui.theme())
        uji.ui.save_theme("gone")
        ui.theme:restore()
        assert.equal("kept", uji.ui.theme())
        ui:take_notices()
        local raised = 0
        for _, notice in ipairs(ui.notices) do
            raised = raised + (has(notice, "saved theme: no theme named gone") and 1 or 0)
        end
        assert.equal(1, raised)
        local ok, err = pcall(uji.ui.save_theme, 42)
        assert.is_false(ok)
        assert.is_true(has(err, "uji.ui.save_theme needs a name"))
    end)

    it("stops a template that asks for a style the theme lacks", { size = { 40, 8 } }, function()
        ui:paint()
        local ctx = ui.theme:context()
        assert.equal(ito.TextStyle({ foreground = ito.Color.cyan, bold = true }), ctx.styles.accent)
        local ok, err = pcall(function()
            return ctx.styles.nope
        end)
        assert.is_false(ok)
        assert.is_true(has(err, "the theme has no style named nope"))
    end)
end)
