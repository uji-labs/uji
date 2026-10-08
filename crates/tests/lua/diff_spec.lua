local agent = require("support.agent")
local app = require("uji.core.app")
local Confirm = require("uji.core.ui.views.confirm")
local sandbox = require("support.sandbox")
local screen = require("support.ui")
local server = require("support.server")
local sys = require("uji.sys")
local tool = require("uji.core.tool")
local ui = require("uji.core.ui")

local GREET = 'def main():\n    name = "world"\n    print("Hello, " + name)\n    return 0\n'
local HI = 'def main():\n    name = "world"\n    print("Hi, " + name)\n    print("bye")\n    return 0\n'
local EDIT = { path = "greet.py", old_string = '    print("Hello, " + name)', new_string = '    print("Hi, " + name)\n    print("bye")' }

local function shape(diff)
    local out = {}
    for _, change in ipairs(diff.changes) do
        for _, line in ipairs(change) do
            local parts = {}
            for _, part in ipairs(line.parts) do
                parts[#parts + 1] = part.changed and "[" .. part.text .. "]" or part.text
            end
            out[#out + 1] = string.format("%s %s %s %s", line.kind, tostring(line.old), tostring(line.new), table.concat(parts))
        end
        out[#out + 1] = "--"
    end
    return out
end

local function numbered(count, changed)
    local out = {}
    for index = 1, count do
        out[index] = (changed and changed[index] or "line " .. index) .. "\n"
    end
    return table.concat(out)
end

local function click(label)
    local row = screen.find(label)
    ui:mouse({ kind = "down", button = "left", row = row, col = 6 })
    ui:mouse({ kind = "up", button = "left", row = row, col = 6 })
end

local function calls(list)
    local mock = agent.serve(function(round)
        if list[round + 1] then
            return server.tool_calls(round, { list[round + 1] })
        end
        return server.text("done")
    end)
    agent.allow_all()
    agent.run({ url = mock.url })
end

local function stored()
    local out = {}
    for _, entry in ipairs(app.store:session(app.session.id):entries()) do
        if entry.message.type == "tool" then
            out[#out + 1] = entry.message
        end
    end
    return out
end

it("gives the changed lines with context, old and new numbers and the changed words", function()
    assert.same({
        "context 1 1 def main():",
        'context 2 2     name = "world"',
        'removed 3 nil     print("[Hello], " + name)',
        'added nil 3     print("[Hi], " + name)',
        'added nil 4 [    print("bye")]',
        "context 4 5     return 0",
        "--",
    }, shape(uji.diff(GREET, HI, "greet.py")))
end)

it("keeps changes far apart separate and refuses what is not text", function()
    local diff = uji.diff(numbered(30), numbered(30, { [2] = "two", [28] = "twenty eight" }), "list.txt")
    assert.equal(2, #diff.changes)
    assert.equal("list.txt", diff.path)
    local ok, err = pcall(uji.diff, nil, "x")
    assert.is_false(ok)
    assert.equal("uji.diff needs the old and the new text", tostring(err):match("uji.diff needs.*"))
end)

it("keeps a diff for edits and overwrites and a summary for reads and new files after a reopen", { timeout = 10 }, function()
    sandbox.file("greet.py", GREET)
    calls({
        { "edit_file", sys.json.encode(EDIT) },
        { "read_file", sys.json.encode({ path = "greet.py" }) },
        { "write_file", sys.json.encode({ path = "new.txt", content = "a\nb\n" }) },
        { "write_file", sys.json.encode({ path = "greet.py", content = GREET }) },
    })
    local edit, read, created, overwrote = unpack(stored())
    assert.equal("edited greet.py at line 3", edit.content)
    assert.same(shape(uji.diff(GREET, HI, "greet.py")), shape(edit.diff))
    assert.equal("Read 5 lines", read.summary)
    assert.truthy(read.content:find("print", 1, true))
    assert.equal("Wrote 2 lines", created.summary)
    assert.is_nil(created.diff)
    assert.same(shape(uji.diff(HI, GREET, "greet.py")), shape(overwrote.diff))
end)

it("folds a long diff and opens it on a click", { size = { 80, 40 } }, function()
    app.session:append({
        type = "tool",
        tool_call_id = "a",
        name = "write_file",
        content = "x",
        diff = uji.diff("", numbered(30), "list.txt"),
    })
    screen.rows(true)
    assert.is_not_nil(screen.find("⎿  Added 30 lines"))
    assert.is_not_nil(screen.find("… +10 lines"))
    assert.is_nil(screen.find("30 + line 30"))
    click("… +10 lines")
    assert.is_not_nil(screen.find("30 + line 30"))
end)

it("shows only a read's summary until it is clicked", { size = { 80, 20 } }, function()
    app.session:append({
        type = "tool",
        tool_call_id = "a",
        name = "read_file",
        content = "    1| alpha\n    2| beta",
        summary = "Read 2 lines",
    })
    screen.rows(true)
    assert.is_not_nil(screen.find("⎿  Read 2 lines"))
    assert.is_nil(screen.find("2| beta"))
    click("Read 2 lines")
    assert.is_not_nil(screen.find("2| beta"))
end)

it("shows the summary of a result whose diff has no changes", { size = { 80, 20 } }, function()
    local same = uji.diff(GREET, GREET, "greet.py")
    assert.same({}, same.changes)
    app.session:append({ type = "tool", tool_call_id = "a", name = "write_file", content = "x", diff = same, summary = "Wrote 4 lines" })
    screen.rows(true)
    assert.is_not_nil(screen.find("⎿  Wrote 4 lines"))
end)

it("shows the edit it asks about in the approval prompt", { size = { 80, 24 } }, function()
    sandbox.file("greet.py", GREET)
    local question, detail, preview = app.agent:question("edit_file", tool.described("edit_file"), EDIT)
    assert.equal("greet.py", detail)
    ui:present(Confirm({ title = question, body = detail, preview = preview }))
    screen.rows(true)
    assert.is_not_nil(screen.find('3 -     print("Hello, " + name)'))
    assert.is_not_nil(screen.find('4 +     print("bye")'))
end)

it("names and previews a tool that another agent runs from its display", { size = { 80, 24 } }, function()
    sandbox.file("greet.py", GREET)
    uji.tool.display("Edit", {
        label = "Update",
        subject = function(args)
            return args.file_path
        end,
        preview = function(args)
            return uji.diff(uji.fs.read(args.file_path), HI, args.file_path)
        end,
    })
    local arguments = { file_path = "greet.py" }
    app.session:append({
        type = "assistant",
        text = "",
        tool_calls = { { id = "a", name = "Edit", arguments = sys.json.encode(arguments) } },
    })
    screen.rows(true)
    assert.is_not_nil(screen.find("⏺ Update(greet.py)"))
    local _, detail, preview = app.agent:question("Edit", tool.described("Edit"), arguments)
    assert.equal("greet.py", detail)
    assert.same(shape(uji.diff(GREET, HI, "greet.py")), shape(preview))
    assert.is_nil(tool.get("Edit"), "a display is not a tool uji runs")
end)
