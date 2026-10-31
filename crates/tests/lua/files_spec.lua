local Files = require("uji.core.system.files")
local sandbox = require("support.sandbox")
local sys = require("uji.sys")

local function around(target, line, count)
    return Files(require("uji.core.app").session.directory):around(target, line, count)
end

local function symlink(target, path)
    local link = assert(sys.proc.spawn({ "ln", "-s", target, path }))
    assert.equal(0, link:wait().code)
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

it("gives a plugin the data directory and the path helpers it walks with", function()
    sandbox.file("notes/a.txt", "a")
    assert.equal(sandbox.data, uji.data.dir())
    assert.equal("notes", uji.fs.parent("notes/a.txt"))
    assert.equal("file", uji.fs.stat("notes/a.txt").type)
    assert.equal(1, uji.fs.stat("notes/a.txt").size)
    assert.is_nil(uji.fs.stat("notes/missing.txt"))
    assert.is_nil(uji.fs.parent("/"))
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

it("reads, previews and writes through a symlink before a parent component", function()
    sandbox.file("note.txt", "neighbor")
    sandbox.write(sandbox.root .. "/other/note.txt", "target")
    assert(sys.fs.mkdir(sandbox.root .. "/other/sub"))
    symlink("../other/sub", sandbox.work .. "/link")
    assert.equal("target", uji.fs.read("link/../note.txt"))
    assert.same({ "    1| target" }, around("link/../note.txt", 1, 1))
    assert(sys.fs.mkdir(sandbox.root .. "/other/sub/nested"))
    assert.equal("target", uji.fs.read("link/nested/../../note.txt"))
    assert.equal("target", Files(sandbox.work .. "/link"):read("../note.txt"))
    assert(uji.fs.write("link/../note.txt", "updated"))
    assert.equal("updated", sandbox.read(sandbox.root .. "/other/note.txt"))
    assert.equal("neighbor", uji.fs.read("note.txt"))
end)

it("creates missing files after a symlink and a parent component", function()
    assert(sys.fs.mkdir(sandbox.root .. "/other/sub"))
    symlink("../other/sub", sandbox.work .. "/link")
    assert(uji.fs.write("link/../new/deep.txt", "created"))
    assert.equal("created", sandbox.read(sandbox.root .. "/other/new/deep.txt"))
    assert.is_nil(uji.fs.stat("new/deep.txt"))
end)

it("keeps glob matches readable after a symlink and a parent component", function()
    sandbox.file("note.txt", "neighbor")
    sandbox.write(sandbox.root .. "/other/note.txt", "target")
    assert(sys.fs.mkdir(sandbox.root .. "/other/sub"))
    symlink("../other/sub", sandbox.work .. "/link")
    local matches = uji.fs.glob("link/../*.txt")
    assert.equal(1, #matches)
    assert.equal("target", uji.fs.read(matches[1]))
end)

it("does not redirect a failed parent traversal to a neighboring file", function()
    sandbox.file("note.txt", "neighbor")
    sandbox.file("regular", "not a directory")
    symlink("missing", sandbox.work .. "/dangling")
    for _, path in ipairs({ "regular/../note.txt", "dangling/../note.txt" }) do
        assert.is_nil((uji.fs.read(path)))
        assert.is_nil((uji.fs.write(path, "wrong")))
    end
    assert.equal("neighbor", uji.fs.read("note.txt"))
end)

it("resolves a path to the file the system would touch", function()
    sandbox.file("note.txt", "note")
    assert.equal(sys.fs.realpath(sandbox.work .. "/note.txt"), sys.fs.canonical(sandbox.work .. "/note.txt"))
    assert.equal(sys.fs.realpath(sandbox.work) .. "/new.txt", sys.fs.canonical(sandbox.work .. "/new.txt"))
    assert.equal(sys.fs.realpath(sandbox.work) .. "/b.txt", sys.fs.canonical(sandbox.work .. "/a/../b.txt"))
end)

it("follows a dangling link to the path the system creates", function()
    assert(sys.fs.mkdir(sandbox.root .. "/other"))
    symlink("secret.env", sandbox.root .. "/other/alias")
    assert.equal(sys.fs.realpath(sandbox.root .. "/other") .. "/secret.env", sys.fs.canonical(sandbox.root .. "/other/alias"))
end)

it("does not follow a link that points at itself", function()
    symlink("self", sandbox.work .. "/self")
    assert.equal(sys.fs.realpath(sandbox.work) .. "/self", sys.fs.canonical(sandbox.work .. "/self"))
end)
