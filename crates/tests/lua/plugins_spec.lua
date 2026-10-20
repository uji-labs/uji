local cli = require("uji.core.cli")
local packs = require("uji.core.packs")
local paths = require("uji.core.paths")
local plugins = require("uji.core.plugins")
local sandbox = require("support.sandbox")
local sys = require("uji.sys")

local function pack(name, modules)
    local root = sandbox.work .. "/" .. name
    for _, module in ipairs(modules) do
        sandbox.write(root .. "/lua/" .. module .. "/init.lua", "return { setup = function() end }\n")
    end
    packs.add({ { dir = root } })
    return root
end

local function written(name, root)
    return sandbox.read((root or sandbox.cfg) .. "/plugin/" .. name .. ".lua")
end

local function exists(path)
    return sys.fs.stat(path) ~= nil
end

local function drain(proc)
    local text = {}
    for line in proc:lines() do
        text[#text + 1] = line
    end
    return table.concat(text, "\n")
end

local function git(cwd, ...)
    local proc = sys.proc.spawn({ "git", ... }, { cwd = cwd })
    if not proc then
        return false
    end
    local output = drain(proc)
    return proc:wait().success, output
end

it("adds a plugin that an installed pack offers", function()
    pack("first", { "alpha" })
    local path = assert(plugins.add("alpha"))
    assert.equal(sandbox.cfg .. "/plugin/alpha.lua", path)
    assert.equal('require("alpha").setup({})\n', written("alpha"))
    assert(loadfile(path))
end)

it("adds a plugin from a pack it installs", function()
    local root = pack("second", { "beta" })
    local path = assert(plugins.add(root))
    assert.equal(sandbox.cfg .. "/plugin/beta.lua", path)
    assert.equal(string.format('uji.pack.add({ { dir = %q } })\nrequire("beta").setup({})\n', root), written("beta"))
    assert(loadfile(path))
end)

it("names the modules a pack of several offers", function()
    local root = pack("third", { "one", "two" })
    local path, err = plugins.add(root)
    assert.is_nil(path)
    assert.is_true(err:find("one, two", 1, true) ~= nil)
    assert.is_false(exists(sandbox.cfg .. "/plugin/one.lua"))
    assert.is_false(exists(sandbox.cfg .. "/plugin/two.lua"))
end)

it("adds the module --name picks", function()
    local root = pack("fourth", { "three", "four" })
    local path = assert(plugins.add(root, { name = "four" }))
    assert.equal(string.format('uji.pack.add({ { dir = %q } })\nrequire("four").setup({})\n', root), written("four"))
    assert(loadfile(path))
end)

it("refuses a --name that is not a module name", function()
    local root = pack("fifth", { "five" })
    for _, name in ipairs({ "../escape", 'x").setup(os.exit', "a/b", "" }) do
        local path, err = plugins.add(root, { name = name })
        assert.is_nil(path)
        assert.is_true(err:find("invalid plugin name", 1, true) ~= nil, "refused " .. name)
    end
    assert.is_false(exists(sandbox.cfg .. "/plugin/five.lua"))
end)

it("refuses an empty pack argument", function()
    local path, err = plugins.add("")
    assert.is_nil(path)
    assert.is_true(err:find("needs a name or a pack", 1, true) ~= nil)
    path, err = plugins.add(nil)
    assert.is_nil(path)
    assert.is_true(err:find("needs a name or a pack", 1, true) ~= nil)
end)

it("leaves the config alone when the pack is not a directory", function()
    local root = sandbox.work .. "/missing"
    local path, err = plugins.add(root)
    assert.is_nil(path)
    assert.is_true(err:find("no such directory", 1, true) ~= nil)
    assert.is_false(exists(sandbox.cfg .. "/plugin/missing.lua"))
end)

it("refuses a revision for a directory pack", function()
    local root = pack("sixth", { "six" })
    local path, err = plugins.add(root, { rev = "v1" })
    assert.is_nil(path)
    assert.is_true(err:find("--rev needs a pack to clone", 1, true) ~= nil)
    assert.is_false(exists(sandbox.cfg .. "/plugin/six.lua"))
end)

it("clones a pack at the revision it records", function()
    local root = sandbox.work .. "/repo"
    sandbox.write(root .. "/lua/seven/init.lua", "return { setup = function() end }\n")
    if not git(root, "--version") then
        return
    end
    assert(git(root, "init", "-q"))
    assert(git(root, "add", "-A"))
    assert(git(root, "-c", "user.name=uji", "-c", "user.email=uji@example.com", "commit", "-qm", "one"))
    local url = "file://" .. root
    local path = assert(plugins.add(url, { rev = "HEAD" }))
    assert.equal(string.format('uji.pack.add({ { url = %q, commit = "HEAD" } })\nrequire("seven").setup({})\n', url), written("seven"))
    assert(loadfile(path))
end)

it("keeps an existing plugin file unless forced", function()
    pack("seventh", { "eight" })
    assert(plugins.add("eight"))
    sandbox.write(sandbox.cfg .. "/plugin/eight.lua", 'require("eight").setup({ topics = true })\n')
    local path, err = plugins.add("eight")
    assert.is_nil(path)
    assert.is_true(err:find("already enabled", 1, true) ~= nil)
    assert.equal('require("eight").setup({ topics = true })\n', written("eight"))
    assert(plugins.add("eight", { force = true }))
    assert.equal('require("eight").setup({})\n', written("eight"))
end)

it("does not overwrite a plugin file it did not write", function()
    pack("eighth", { "nine" })
    sandbox.write(sandbox.cfg .. "/plugin/nine.lua", "print('mine')\n")
    local path, err = plugins.add("nine")
    assert.is_nil(path)
    assert.is_true(err:find("already enabled", 1, true) ~= nil)
    assert.equal("print('mine')\n", written("nine"))
end)

it("refuses to write through a symlink", function()
    pack("ninth", { "ten" })
    sandbox.write(sandbox.work .. "/target.lua", "print('target')\n")
    assert(sys.fs.mkdir(sandbox.cfg .. "/plugin"))
    local link = sandbox.cfg .. "/plugin/ten.lua"
    local made = assert(sys.proc.spawn({ "ln", "-s", sandbox.work .. "/target.lua", link }))
    local output = drain(made)
    assert(made:wait().success, output)
    local path, err = plugins.add("ten", { force = true })
    assert.is_nil(path)
    assert.is_true(err:find("symlink", 1, true) ~= nil)
    assert.equal("print('target')\n", sandbox.read(sandbox.work .. "/target.lua"))
end)

it("leaves a plugin that init.lua enables alone", function()
    local other = sandbox.dir("other")
    sandbox.write(other.cfg .. "/init.lua", 'require("thirteen").setup({})\n')
    paths.overrides.config = other.cfg
    pack("tenth", { "thirteen" })
    local path, err = plugins.add("thirteen")
    assert.is_nil(path)
    assert.is_true(err:find("enabled in", 1, true) ~= nil)
    path, err = plugins.add("thirteen", { force = true })
    assert.is_nil(path)
    assert.is_true(err:find("enabled in", 1, true) ~= nil)
    assert.is_false(exists(other.cfg .. "/plugin/thirteen.lua"))
    path, err = plugins.remove("thirteen")
    assert.is_nil(path)
    assert.is_true(err:find("enabled in", 1, true) ~= nil)
    assert.equal('require("thirteen").setup({})\n', sandbox.read(other.cfg .. "/init.lua"))
end)

it("removes only the file it wrote", function()
    pack("eleventh", { "eleven", "twelve" })
    sandbox.write(sandbox.cfg .. "/plugin/all.lua", 'require("eleven").setup({})\nrequire("twelve").setup({})\n')
    local path, err = plugins.remove("eleven")
    assert.is_nil(path)
    assert.is_true(err:find("enabled in", 1, true) ~= nil)
    assert.equal('require("eleven").setup({})\nrequire("twelve").setup({})\n', written("all", sandbox.cfg))
end)

it("refuses to remove an invalid name", function()
    local path, err = plugins.remove("../../etc/passwd")
    assert.is_nil(path)
    assert.is_true(err:find("invalid plugin name", 1, true) ~= nil)
end)

it("runs the command line", function()
    pack("twelfth", { "fifteen" })
    local lines, err = plugins.cli({ positional = { "list" }, flags = {} })
    assert.is_nil(err)
    assert.is_true(table.concat(lines, "\n"):find("fifteen", 1, true) ~= nil)
    local added, problem = plugins.cli({ positional = { "add", "fifteen" }, flags = {} })
    assert.is_nil(problem)
    assert.equal(sandbox.cfg .. "/plugin/fifteen.lua", added[1])
    lines = assert(plugins.cli({ positional = { "list" }, flags = {} }))
    assert.is_true(table.concat(lines, "\n"):find("fifteen%s+on") ~= nil)
    assert(plugins.cli({ positional = { "remove", "fifteen" }, flags = {} }))
    local _, missing = plugins.cli({ positional = { "add" }, flags = {} })
    assert.is_true(missing:find("needs a name or a pack", 1, true) ~= nil)
    local _, unknown = plugins.cli({ positional = {}, flags = {} })
    assert.is_true(unknown:find("plugin needs", 1, true) ~= nil)
end)

it("writes a file Lua can load when the pack path is odd", function()
    local root = sandbox.work .. '/odd"pack'
    sandbox.write(root .. "/lua/seventeen/init.lua", "return { setup = function() end }\n")
    local path = assert(plugins.add(root))
    assert(loadfile(path))
end)

it("never offers uji itself as a plugin", function()
    local path, err = plugins.add("uji")
    assert.is_nil(path)
    assert.is_true(err:find("no installed pack offers uji", 1, true) ~= nil)
end)

it("reports a plugin directory it cannot create", function()
    local other = sandbox.dir("blocked")
    sandbox.write(other.cfg .. "/init.lua", "")
    sandbox.write(other.cfg .. "/plugin", "not a directory\n")
    paths.overrides.config = other.cfg
    pack("thirteenth", { "fourteen" })
    local path, err = plugins.add("fourteen")
    assert.is_nil(path)
    assert.is_true(err:find("plugin", 1, true) ~= nil)
end)

it("does not touch init.lua", function()
    local before = sandbox.read(sandbox.cfg .. "/init.lua")
    pack("fourteenth", { "sixteen" })
    assert(plugins.add("sixteen"))
    assert(plugins.remove("sixteen"))
    assert.equal(before, sandbox.read(sandbox.cfg .. "/init.lua"))
end)

it("parses plugin add with its flags", function()
    local parsed = cli.parse({ "uji", "plugin", "add", "probe", "--name", "other", "--rev", "v1", "--force" })
    assert.equal("plugin", parsed.command)
    assert.same({ "add", "probe" }, parsed.positional)
    assert.equal("other", parsed.flags.name)
    assert.equal("v1", parsed.flags.rev)
    assert.is_true(parsed.flags.force)
end)
