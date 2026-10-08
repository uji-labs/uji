local Files = require("uji.core.system.files")
local sandbox = require("support.sandbox")
local sys = require("uji.sys")

local function around(target, line, count)
    return Files(require("uji.core.app").session.directory):around(target, line, count)
end

it("numbers the lines around a hit in a preview", function()
    local rows = {}
    for n = 1, 300 do
        rows[n] = "row " .. n
    end
    sandbox.file("rows.txt", table.concat(rows, "\n") .. "\n")
    assert.same({
        "  149| row 149",
        "  150| row 150",
        "  151| row 151",
        "  152| row 152",
    }, around("rows.txt", 150, 4))
    assert.same({ "    1| row 1", "    2| row 2", "    3| row 3" }, around("rows.txt", 1, 3))
    assert.same({}, around("rows.txt", 400, 4))
end)

it("drops carriage returns in a preview and refuses what it cannot show", function()
    sandbox.file("crlf.txt", "a\r\nb\r\n")
    sandbox.file("bin.dat", "x\0y")
    sandbox.file("dir/inner.txt", "inside")
    assert.same({ "    1| a", "    2| b" }, around("crlf.txt", 1, 2))
    local binary, binary_error = around("bin.dat", 1, 2)
    assert.is_nil(binary)
    assert.equal("bin.dat looks like a binary file", binary_error)
    local directory, directory_error = around("dir", 1, 2)
    assert.is_nil(directory)
    assert.equal("dir is a directory, not a file", directory_error)
end)

it("reads plugin files from the config and the nearest project", function()
    sandbox.write(sandbox.cfg .. "/agents/mine.md", "mine")
    assert(require("uji.sys").fs.mkdir(sandbox.cfg .. "/agents/nested"))
    sandbox.write(sandbox.root .. "/.uji/agents/repo.md", "repo")
    sandbox.file("notes/a.txt", "a")
    local found = {}
    for _, file in ipairs(uji.config.files("agents", { project = true })) do
        found[#found + 1] = file.name .. "=" .. file.text .. (file.project and " project" or "")
    end
    assert.same({ "mine.md=mine", "repo.md=repo project" }, found)
    local mine = {}
    for _, file in ipairs(uji.config.files("agents")) do
        mine[#mine + 1] = file.name
    end
    assert.same({ "mine.md" }, mine)
    local entries = uji.fs.list("notes")
    assert.equal("a.txt", entries[1].name)
    assert.equal("file", entries[1].type)
end)

it("reaches paths outside the working directory and from the home directory", function()
    sandbox.write(sandbox.root .. "/outside/a.txt", "a")
    assert.equal("a", uji.fs.read("../outside/a.txt"))
    assert.equal("a", uji.fs.read(sandbox.root .. "/outside/a.txt"))
    assert.same({ sandbox.root .. "/outside/a.txt" }, uji.fs.glob(sandbox.root .. "/out*/*.txt"))
    assert.same({ sandbox.root .. "/outside/a.txt" }, uji.fs.glob(sandbox.work .. "/./../out*/*.txt"))
    assert.equal(sys.os.home() .. "/notes.txt", Files(sandbox.work):resolve("~/notes.txt"))
    assert.equal(sys.os.home(), Files(sandbox.work):resolve("~"))
    assert.equal(sys.os.home(), sys.os.expand("~"))
    assert.equal(sandbox.work .. "/a/c", Files(sandbox.work):resolve("./a/b/../c"))
    assert.equal("/etc", Files(sandbox.work):resolve("/../etc"))
end)

it("joins, splits and compares paths in the kernel", function()
    assert.equal("/a/b/c.txt", sys.fs.join("/a", "b", "c.txt"))
    assert.equal("/a/b", sys.fs.parent("/a/b/c.txt"))
    assert.is_nil(sys.fs.parent("/"))
    assert.equal("c.txt", sys.fs.name("/a/b/c.txt"))
    assert.is_true(sys.fs.absolute("/a"))
    assert.is_false(sys.fs.absolute("a/b"))
    assert.is_true(sys.fs.inside("/a/b/../b/c", "/a/b"))
    assert.is_false(sys.fs.inside("/a/bc", "/a/b"))
    assert.equal("~/x/y", sys.os.shorten(sys.os.home() .. "/x/y"))
    assert.equal("~", sys.os.shorten(sys.os.home()))
    assert.equal("/elsewhere/x", sys.os.shorten("/elsewhere/x"))
end)

it("gives plugins the kernel's join and refuses to open nothing", function()
    assert.equal("~/.claude/projects", uji.fs.join("~", ".claude", "projects"))
    assert.has_error(function()
        uji.ui.open("")
    end, "uji.ui.open needs a file or link to open")
end)

it("keeps a plugin's own file in the data directory", function()
    assert.is_true(uji.data.write("notes.json", "{}"))
    assert.equal("{}", uji.data.read("notes.json"))
    assert.equal("{}", sandbox.read(sandbox.data .. "/notes.json"))
    assert.is_nil((uji.data.read("missing.json")))
    assert.is_false((pcall(uji.data.read, "../escape.json")))
    assert.equal(uji.session.info().directory, uji.session.info().short_directory)
end)

it("matches a pattern in a working directory whose name has brackets", function()
    sandbox.file("[x]/f.txt", "f")
    assert.same({ "f.txt" }, Files(sandbox.work .. "/[x]"):glob("*.txt"))
end)
