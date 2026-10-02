local Roots = require("uji.core.system.roots")
local sandbox = require("support.sandbox")

local function around(target, line, count)
    local roots = Roots(require("uji.core.app").session.directory, {}, false)
    return roots:around(target, line, count)
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
    local listed, err = uji.fs.list("..")
    assert.is_nil(listed)
    assert.is_not_nil(err)
end)
