local default = require("uji.themes.default")
local diagnostics = require("uji.core.diagnostics")
local paths = require("uji.core.paths")
local screen = require("support.ui")
local sys = require("uji.sys")
local ui = require("uji.core.ui")

local function has(value, part)
    return tostring(value):find(part, 1, true) ~= nil
end

it("records a broken screen once with its traceback, and shows no notice", { size = { 40, 10 } }, function()
    uji.ui.configure({
        theme = default({
            views = {
                [uji.ui.Screen] = function()
                    return { "a table" }
                end,
            },
        }),
    })
    screen.rows(true)
    screen.rows(true)
    local entries = uji.diagnostics.list()
    assert.equal(1, #entries)
    assert.equal("screen", entries[1].source)
    assert.is_true(has(entries[1].text, "a view must give a view, not a table"))
    assert.is_true(has(entries[1].text, "stack traceback"))
    ui:take_notices()
    assert.same({}, ui.notices)
end)

it("records a broken view once however many messages use it", { size = { 40, 20 } }, function()
    uji.ui.configure({
        theme = default({
            views = {
                [uji.ui.UserMessage] = function()
                    error("no user today", 0)
                end,
            },
        }),
    })
    for index = 1, 5 do
        require("uji.core.app").session:append({ type = "user", text = "hello " .. index })
    end
    screen.rows(true)
    local entries = uji.diagnostics.list()
    assert.equal(1, #entries)
    assert.equal("view", entries[1].source)
    assert.is_true(has(entries[1].text, "no user today"))
end)

it("lists the newest first and shows a whole entry in the preview", function()
    diagnostics.report("render", { text = "older", trace = "stack traceback:\n\tsomewhere" })
    diagnostics.report("modal", { text = "newer\nsecond line" })
    local asked
    uji.ui.pick = function(opts)
        asked = opts
    end
    require("uji.core.command").run("diagnostics")
    assert.equal(2, #asked.items)
    assert.is_true(has(asked.label(asked.items[1]), "modal  newer"))
    assert.is_true(has(asked.label(asked.items[2]), "render  older"))
    assert.same({ "older", "stack traceback:", "\tsomewhere" }, asked.preview(asked.items[2]))
end)

it("says when there is nothing to show", function()
    require("uji.core.command").run("diagnostics")
    ui:take_notices()
    assert.is_true(has(table.concat(ui.notices, "\n"), "no diagnostics yet"))
end)

it("keeps the log to the newest entries", function()
    local big = string.rep("x", 400 * 1024)
    for index = 1, 4 do
        diagnostics.report("render", { text = index .. big })
    end
    local entries = uji.diagnostics.list()
    assert.equal("4", entries[1].text:sub(1, 1))
    assert.is_true(#entries < 4)
    assert.is_true(sys.fs.stat(paths.data() .. "/diagnostics.log").size <= 1024 * 1024)
end)
