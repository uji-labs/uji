local agent = require("support.agent")
local packs = require("uji.core.packs")
local paths = require("uji.core.paths")
local sandbox = require("support.sandbox")
local sys = require("uji.sys")

local SETUP = "uji.builtin.commands.setup"
local PLUGINS = "uji-labs/uji-plugins"

local function pack(names)
    local env = sandbox.dir("packs")
    for _, name in ipairs(names) do
        sandbox.write(env.root .. "/lua/" .. name .. "/init.lua", "return {}")
    end
    packs.add_root(env.root)
    return env.root
end

local function offered()
    for _, name in ipairs(uji.command.list()) do
        if name == "setup" then
            return true
        end
    end
    return false
end

local function loaded()
    uji.command.remove("setup")
    package.loaded[SETUP] = nil
    require(SETUP)
end

local function signed_out(name)
    local env = sandbox.dir(name)
    paths.overrides.config = env.cfg
    loaded()
    return env
end

local function unconfigured(name)
    local env = signed_out(name)
    agent.provider("http://127.0.0.1:9", 100000)
    uji.model.use({ provider = "test", model = "m" })
    return env
end

local function ran(line)
    local seen = { notices = {} }
    local submit, add = uji.session.submit, uji.pack.add
    uji.session.submit = function(text)
        seen.sent = text
    end
    uji.pack.add = function(specs)
        seen.packs = specs
    end
    local listening = uji.on("notice", function(notice)
        seen.notices[#seen.notices + 1] = notice.text
    end)
    require("uji.core.command").run(line)
    uji.off("notice", listening)
    uji.session.submit, uji.pack.add = submit, add
    return seen
end

local function has(value, part)
    return value ~= nil and value:find(part, 1, true) ~= nil
end

local function turn()
    local _, gathered = require("uji.core.context").gather("")
    local text = {}
    for _, message in ipairs(gathered) do
        text[#text + 1] = message.text
    end
    return table.concat(text, "\n")
end

it("is offered only until a config is there", function()
    assert.is_false(offered(), "this run started with a config")
    unconfigured("fresh")
    assert.is_true(offered(), "a run without a config has it")
    ran("setup")
    loaded()
    assert.is_false(offered(), "the config it wrote takes it away")
end)

it("writes a starter config and a guide, then starts the interview", function()
    local env = unconfigured("fresh")
    local seen = ran("setup")
    local init = sandbox.read(env.cfg .. "/init.lua")
    assert.is_function(load(init), "the starter config is Lua that compiles")
    assert.is_true(has(init, 'require("uji.builtin.defaults")'), init)
    assert.is_true(has(init, 'uji.pack.add({ "' .. PLUGINS .. '" })'), init)
    assert.is_true(has(init, string.format("%q", sys.os.shorten(env.cfg .. "/.agents/skills"))), init)
    assert.is_nil(init:find("%$%u"), init)
    local skill = env.cfg .. "/.agents/skills/uji-config"
    local guide = sandbox.read(skill .. "/SKILL.md")
    assert.is_true(has(guide, "name: uji-config"), guide)
    assert.is_true(has(guide, "version " .. require("uji.version")), guide)
    assert.is_nil(guide:find("%$%u"), guide)
    assert.is_true(has(sandbox.read(skill .. "/docs/SUMMARY.md"), "api/index.md"), "the guide comes with the book")
    assert.is_true(has(sandbox.read(skill .. "/docs/api/tool.md"), "uji.tool.add"), "a page holds its text")
    assert.same({ PLUGINS }, seen.packs, "the plugins are on disk before the questions start")
    assert.same({ "started your config at " .. sys.os.shorten(env.cfg .. "/init.lua") }, seen.notices)
    assert.equal("Set up uji for me.", seen.sent, "the transcript keeps the request alone")
    local briefed = turn()
    assert.is_true(has(briefed, "Interview them with the ask_user tool"), briefed)
    assert.is_true(has(briefed, "Do not read files or run\ncommands before it."), briefed)
    assert.is_true(has(briefed, "Then call reload_config and end your turn."), briefed)
    assert.is_not_nil(require("uji.core.tool").get("reload_config"), "so each answer shows up as it is given")
    assert.is_true(has(briefed, "Their install:"), briefed)
    assert.is_true(has(briefed, "init.lua: " .. env.cfg .. "/init.lua, written just now"), briefed)
    assert.is_true(has(briefed, "guide: " .. skill .. "/SKILL.md"), briefed)
    assert.is_true(has(briefed, "machine: " .. uji.os.platform .. ", shell "), briefed)
    assert.is_true(has(briefed, "themes: default"), briefed)
    assert.is_true(has(briefed, "Request: Set up uji for me."), briefed)
    assert.equal("", turn(), "the map goes with one turn only")
end)

it("leaves a config that is already there as it was", function()
    local env = unconfigured("kept")
    sandbox.write(env.cfg .. "/init.lua", "-- mine\n")
    local seen = ran("setup")
    assert.equal("-- mine\n", sandbox.read(env.cfg .. "/init.lua"))
    assert.same({}, seen.notices)
    assert.is_true(has(turn(), "theirs from before and left as it was"))
end)

it("sends what the person typed as the request", function()
    unconfigured("typed")
    local seen = ran("setup I only want a dark theme")
    assert.equal("I only want a dark theme", seen.sent)
    assert.is_true(has(turn(), "Request: I only want a dark theme"))
end)

it("puts what the packs offer on the map", function()
    unconfigured("offers")
    local root = pack({ "widget" })
    sandbox.write(root .. "/lua/uji/themes/dusk.lua", "return {}")
    ran("setup")
    local briefed = turn()
    assert.is_true(has(briefed, root .. ": widget"), briefed)
    assert.is_true(has(briefed, "themes: default, dusk"), "a theme from a pack added in this run is on the map")
end)

it("hands the model what it needs, so the first thing it does is ask", function()
    local env = unconfigured("handed")
    pack({ "statusline", "widget" })
    ran("setup")
    local briefed = turn()
    local init = sandbox.read(env.cfg .. "/init.lua")
    assert.is_true(has(briefed, "Their init.lua:\n" .. init), "their config as it is now")
    assert.is_true(has(briefed, "--- api/tool.md\n## uji.tool.policy(rules, opts)"), "how approvals are written")
    assert.is_false(has(briefed, "## uji.tool.add"), "only the part of the page that this setup uses")
    assert.is_true(has(briefed, "--- plugins/statusline.md\n# statusline"), "the page of a plugin a pack offers")
    assert.is_false(has(briefed, "--- plugins/widget.md"), "a plugin without a page has none")
    assert.is_false(has(briefed, "--- plugins/websearch.md"), "nor does a plugin no pack offers")
    assert.is_true(has(briefed, "--- configuration/themes.md\n# Themes"), "how a theme is chosen")
    assert.is_true(has(briefed, 'uji.ui.configure({ theme = "harbor" })'), briefed)
    assert.is_false(has(briefed, "## Building a theme"), "without the pages on building one")
    assert.is_true(has(briefed, "--- api/keymap.md\n# uji.keymap"), "how keys are bound")
end)

it("asks for a sign-in before it writes anything", function()
    local env = signed_out("signedout")
    local seen = ran("setup")
    assert.same({ "sign in with /login first, then run /setup" }, seen.notices)
    assert.is_nil(seen.sent)
    assert.is_nil(sys.fs.stat(env.cfg .. "/init.lua"))
    assert.is_nil(sys.fs.stat(env.cfg .. "/.agents"))
end)

it("asks a question as a choice and reports what the person picked", function()
    local ask = require("uji.core.tool").get("ask_user")
    local asked
    local select = uji.ui.select
    uji.ui.select = function(opts)
        asked = opts
        return opts.items[2]
    end
    local result = ask.run({ question = "which backend?", options = { "exa", "searxng" } }, {})
    uji.ui.select = select
    assert.equal("which backend?", asked.title)
    assert.equal("exa", asked.label(asked.items[1]))
    assert.equal("searxng", asked.label(asked.items[2]))
    assert.equal("the person chose: searxng", result)
end)

it("asks a question as a choice with a description for each, and reports what the person picked", function()
    local ask = require("uji.core.tool").get("ask_user")
    local asked
    local pick = uji.ui.pick
    uji.ui.pick = function(opts)
        asked = opts
        return opts.items[2]
    end
    local options = {
        { label = "exa", description = "hosted, needs a key" },
        { label = "searxng", description = "self hosted, no key" },
    }
    assert.equal("the person chose: searxng", ask.run({ question = "which backend?", options = options }, {}))
    uji.ui.pick = pick
    assert.equal("which backend?", asked.title)
    assert.equal("searxng", asked.label(asked.items[2]))
    assert.same({ "self hosted, no key" }, asked.preview(asked.items[2]))
end)

it("asks a question that the person types, and reports a closed one", function()
    local ask = require("uji.core.tool").get("ask_user")
    local prompt = uji.ui.prompt
    uji.ui.prompt = function(opts)
        return opts.title == "which url?" and "https://search.example" or nil
    end
    assert.equal("the person answered: https://search.example", ask.run({ question = "which url?" }, {}))
    assert.equal("the person closed the question without answering", ask.run({ question = "which key?" }, {}))
    assert.equal("error: ask_user needs a question", ask.run({}, {}))
    uji.ui.prompt = prompt
end)
