local app = require("uji.core.app")
local Confirm = require("uji.core.ui.views.confirm")
local keys = require("uji.core.ui.keys")
local screen = require("support.ui")
local ui = require("uji.core.ui")

local function trimmed(row)
    return (row:gsub("%s+$", ""))
end

local function press(...)
    for _, key in ipairs({ ... }) do
        ui:key(keys.chord(key))
    end
    return screen.rows(true)
end

local function has(rows, part)
    for _, row in ipairs(rows) do
        if row:find(part, 1, true) then
            return true
        end
    end
    return false
end

describe("views for plugins", function()
    it("draws a toolbar item a plugin declares and keeps its state", { size = { 30, 8 } }, function()
        local kit = require("ito")
        local Badge = kit.view(function()
            local taps = kit.state(0)
            return kit.HStack({
                kit.Text("taps " .. taps.value):foreground(kit.rgb(0xff8800)):bold(),
                kit.Spacer(),
                kit.Text("end"),
            }):on_tap(function()
                taps.value = taps.value + 1
            end)
        end)
        uji.ui.toolbar({ kit.ToolbarItem(kit.ToolbarPlacement.bottom_bar, Badge) })
        local rows = screen.rows(true)
        assert.equal("taps 0" .. string.rep(" ", 21) .. "end", rows[8])
        assert.equal("#FF8800", ui.screen:spans(7)[1].fg)
        ui:mouse({ kind = "down", button = "left", row = 7, col = 1 })
        ui:mouse({ kind = "up", button = "left", row = 7, col = 1 })
        assert.equal("taps 1", trimmed(screen.rows(true)[8]):sub(1, 6))
    end)

    it("shows an overlay whose focused list takes the keys", { size = { 40, 12 } }, function()
        local kit = require("ito")
        local chosen
        local handle
        handle = uji.ui.overlay(function()
            return kit.VStack({
                kit.Text("Pick a colour"):bold(),
                kit.List({ "red", "green", "blue" }, function(item, _, selected)
                    return kit.Text((selected and "> " or "  ") .. item)
                end)
                    :focused()
                    :on_choose(function(item)
                        chosen = item
                        handle:close(item)
                    end),
            }):border(kit.theme().borders.rounded)
        end)
        local rows = screen.rows(true)
        assert.is_true(has(rows, "Pick a colour"))
        assert.is_true(has(rows, "> red"))
        rows = press("down", "down")
        assert.is_true(has(rows, "> blue"))
        press("enter")
        assert.equal("blue", chosen)
        assert.is_nil(ui.modal)
        uji.ui.overlay(function()
            return kit.Text("closes with esc")
        end)
        assert.is_true(has(screen.rows(true), "closes with esc"))
        press("esc")
        assert.is_nil(ui.modal)
    end)

    it("gives the keys to an open overlay, and back to the screen once it closes", { size = { 40, 12 } }, function()
        local kit = require("ito")
        local query = kit.state("")
        uji.ui.toolbar({
            kit.ToolbarItem(kit.ToolbarPlacement.bottom_bar, function()
                return kit.TextField(query):focused()
            end),
        })
        screen.rows(true)
        press("a")
        assert.equal("a", query.value)
        local chosen
        local handle
        handle = uji.ui.overlay(function()
            return kit.List({ "red", "green" }, function(item, _, selected)
                return kit.Text((selected and "> " or "  ") .. item)
            end)
                :focused()
                :on_choose(function(item)
                    chosen = item
                    handle:close(item)
                end)
                :toolbar({
                    kit.ToolbarItem(kit.ToolbarPlacement.bottom_bar, function()
                        return kit.Text("enter picks")
                    end),
                })
        end)
        local rows = screen.rows(true)
        assert.equal("> red", trimmed(rows[2]:sub(3)))
        assert.equal("enter picks", trimmed(rows[10]:sub(3)))
        press("down", "enter")
        assert.equal("green", chosen)
        assert.equal("a", query.value)
        press("b")
        assert.equal("ab", query.value)
    end)

    it("keeps a covered overlay's state, and hides it under a newer approval", { size = { 40, 12 } }, function()
        local kit = require("ito")
        uji.ui.overlay(function()
            local name = kit.state("")
            return kit.TextField(name):focused()
        end)
        screen.rows(true)
        press("a", "b")
        assert.equal("ab", trimmed(screen.rows(true)[2]:sub(3)):sub(1, 2))
        local other = uji.ui.overlay(function()
            return kit.Text("second")
        end)
        assert.equal("second", trimmed(screen.rows(true)[2]:sub(3)))
        other:close()
        assert.equal("ab", trimmed(screen.rows(true)[2]:sub(3)):sub(1, 2))
        local approval = ui:present(Confirm({ title = "Allow?", body = "run it" }))
        local rows = screen.rows(true)
        assert.is_true(has(rows, "1. Yes, proceed (y)"))
        assert.is_false(has(rows, "ab"))
        approval:close()
        assert.equal("ab", trimmed(screen.rows(true)[2]:sub(3)):sub(1, 2))
    end)

    it("draws nothing for an overlay whose content is empty", { size = { 40, 12 } }, function()
        for index = 1, 12 do
            app.session:append({ type = "user", text = "line " .. index })
        end
        local before = screen.rows(true)
        uji.ui.overlay(function()
            return nil
        end)
        local after = screen.rows(true)
        assert.same({ unpack(before, 1, 10) }, { unpack(after, 1, 10) })
    end)

    it("lets a theme restyle a plugin's template", { size = { 30, 6 } }, function()
        local kit = require("ito")
        local Badge = uji.ui.template("demo.badge", function(_, props)
            return kit.Text("[" .. props.label .. "]")
        end)
        uji.ui.toolbar({
            kit.ToolbarItem(kit.ToolbarPlacement.top_bar_leading, function()
                return Badge({ label = "ok" })
            end),
        })
        assert.equal("[ok]", trimmed(screen.rows(true)[1]))
        uji.ui.configure({
            theme = require("uji.themes.default")({
                templates = {
                    ["demo.badge"] = function(_, props)
                        return kit.Text("<" .. props.label .. ">")
                    end,
                },
            }),
        })
        assert.equal("<ok>", trimmed(screen.rows(true)[1]))
        assert.has_error(function()
            uji.ui.template("nodot", function() end)
        end)
        assert.has_error(function()
            uji.ui.toolbar("text")
        end, "uji.ui.toolbar takes a list of ito.ToolbarItem")
    end)

    it("draws markdown as a view", { size = { 30, 4 } }, function()
        local kit = require("ito")
        uji.ui.configure({
            theme = require("uji.themes.default")({
                templates = {
                    screen = function()
                        return kit.VStack({ uji.ui.Markdown("# Title\n\nSome **text**.") })
                    end,
                },
            }),
        })
        local rows = screen.rows(true)
        assert.equal("Title", trimmed(rows[1]))
        assert.equal("Some text.", trimmed(rows[3]))
    end)
end)
