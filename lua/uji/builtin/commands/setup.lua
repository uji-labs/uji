local book = require("uji.docs")
local list = require("uji.utils.list")
local paths = require("uji.core.paths")
local scaffold = require("uji.core.scaffold")
local tables = require("uji.core.tables")
local version = require("uji.version")

if scaffold.configured() then
    return
end

local OPENING = "Set up uji for me."
local THEMES = "uji.themes"
local POLICY = "uji.tool.policy"
local RELOAD = "uji.builtin.tools.reload_config"

local PLAYBOOK = [[
You are setting up uji for the person who ran /setup. uji has just written
them a starter config and a guide to configuring uji.

Everything you need to start is below: a map of their install and the machine
they work on, their init.lua as it is now, and the pages of the reference that
this setup uses. Start with the first question. Do not read files or run
commands before it.

Interview them with the ask_user tool, one question at a time. Give the
answers to choose between as options, the one you would pick first, each with
a label and a line on what it means, and say in the question why you would
pick that one. Ask what changes the config and
nothing else, skip what the map already answers, and stop when they say that
is enough. Cover, in this order:
- what uji may do without asking: the commands that run without approval and
  the ones it refuses;
- the plugins their packs offer, a few at a time, with what each one does;
- the look: a theme from the map;
- keys, only when they want different ones.

When the request below already says what they want, set that up and ask only
for the details it leaves out.

After each answer that changes something, put it in the config before the next
question, so they see it take effect:
- Edit init.lua. The write goes through uji's approval, so do not also ask in
  prose.
- Then call reload_config and end your turn. uji restarts on this
  conversation, tells you how the config loaded and hands the turn back to
  you. Fix an error it reports before the next question.

How the config is written:
- Everything goes in init.lua, below what is there. One place per setting, and
  a plugin that is already set up gets its options changed, not a second call.
- Write an option only as a page below gives it. For a plugin they chose that
  has no page below, read its source in its pack first. For a setting no page
  below covers, read its page in the docs folder beside the guide. When
  neither says what a value should be, say so instead of guessing.
- A pack that is missing joins uji.pack.add({...}), as { "user/repo" } or
  { dir = "~/path" }.
- Never put a key or a token in config: provider keys go through /login, and a
  plugin that wants its own key reads it from the environment, so name the
  variable to export instead of taking the value in the conversation.

When the interview is over, tell them that their answers are in init.lua and
already on, and that they can ask uji in plain words to change its own setup,
because the guide stays with their config. Keep the report short.]]

local state = { pending = nil }

local function shown(value)
    return value ~= nil and value ~= "" and tostring(value) or "none"
end

local function joined(values)
    return #values > 0 and table.concat(values, ", ") or "none"
end

local function last(path)
    return path and path:match("([^/]+)$")
end

local function plugins_in(root)
    local pattern = root .. "/" .. paths.MODULE_DIR .. "/*/" .. paths.INIT_FILE
    return list.mapped(uji.fs.glob(pattern) or {}, function(path)
        return path:match("([^/]+)/[^/]+$")
    end)
end

local function offers()
    return list.mapped(uji.pack.list(), function(root)
        return { root = root, plugins = plugins_in(root) }
    end)
end

local function config_files(config)
    return list.mapped(uji.fs.glob(config .. "/" .. paths.PLUGIN_DIR .. "/*.lua") or {}, last)
end

local function themes()
    local names = {}
    for _, module in ipairs(uji.modules(THEMES)) do
        names[module:match("[^.]+$")] = true
    end
    local folder = paths.MODULE_DIR .. "/" .. THEMES:gsub("%.", "/")
    for _, root in ipairs(uji.pack.list()) do
        for _, path in ipairs(uji.fs.glob(root .. "/" .. folder .. "/*.lua") or {}) do
            names[path:match("([^/]+)%.lua$")] = true
        end
    end
    return tables.keys(names)
end

local function signed_in(providers)
    local ids = list.mapped(providers, function(provider)
        return provider.id
    end)
    return list.filtered(ids, uji.auth.authenticated)
end

local function machine()
    return table.concat({
        uji.os.platform,
        "shell " .. shown(last(uji.os.env("SHELL"))),
        "terminal " .. shown(uji.os.env("TERM_PROGRAM") or uji.os.env("TERM")),
        "editor " .. shown(last(uji.os.env("VISUAL") or uji.os.env("EDITOR"))),
    }, ", ")
end

local function sheet(made, offered)
    local model = uji.model.current()
    local providers = uji.provider.list()
    local rows = {
        "uji " .. version,
        "config: " .. made.config,
        "  init.lua: " .. made.init .. (made.started and ", written just now" or ", theirs from before and left as it was"),
        "  plugin/: " .. joined(config_files(made.config)),
        "guide: " .. made.guide,
        "data: " .. shown(paths.data()),
        "machine: " .. machine(),
        "model: " .. shown(model.provider) .. " " .. shown(model.model) .. ", effort " .. shown(model.effort),
        "providers: " .. #providers .. " registered, signed in: " .. joined(signed_in(providers)),
        "tools: " .. joined(uji.tool.list()),
        "themes: " .. joined(themes()),
        "packs:",
    }
    for _, pack in ipairs(offered) do
        rows[#rows + 1] = "  " .. pack.root .. ": " .. joined(pack.plugins)
    end
    return table.concat(rows, "\n")
end

local function lead(text)
    return text:match("^(.-)\n## ") or text
end

local function policy(text)
    local from = text:find("\n## " .. POLICY, 1, true)
    local to = from and text:find("\n## ", from + 1, true)
    return from and text:sub(from + 1, to and to - 1 or -1)
end

local function page(name, cut)
    local text = book[name]
    if not text then
        return nil
    end
    local part = cut and cut(text) or text
    return "--- " .. name .. "\n" .. part:match("^%s*(.-)%s*$")
end

local function reference(offered)
    local named = {}
    for _, pack in ipairs(offered) do
        for _, plugin in ipairs(pack.plugins) do
            named[plugin] = true
        end
    end
    local pages = { page("api/tool.md", policy) }
    for _, plugin in ipairs(tables.keys(named)) do
        pages[#pages + 1] = page("plugins/" .. plugin .. ".md")
    end
    pages[#pages + 1] = page("configuration/themes.md", lead)
    pages[#pages + 1] = page("api/keymap.md")
    return table.concat(pages, "\n\n")
end

local function briefed(made, request)
    local offered = offers()
    return table.concat({
        PLAYBOOK,
        "Their install:\n" .. sheet(made, offered),
        "Their init.lua:\n" .. shown(uji.fs.read(made.init)),
        "The reference this setup uses:\n" .. reference(offered),
        "Request: " .. request,
    }, "\n\n")
end

uji.context.add("setup", function()
    local text = state.pending
    state.pending = nil
    return text and { at = "turn", text = text } or nil
end, { priority = 21 })

uji.command.add("setup", {
    desc = "start your config and make it yours",
    handler = function(args)
        if uji.model.current().provider == "" then
            uji.notify("sign in with /login first, then run /setup")
            return
        end
        local made, err = scaffold.run()
        if not made then
            uji.notify("setup could not write your config: " .. tostring(err))
            return
        end
        if made.started then
            uji.notify("started your config at " .. uji.os.shorten(made.init))
        end
        uji.pack.add({ scaffold.PLUGINS })
        require(RELOAD).grant()
        local request = args ~= "" and args or OPENING
        state.pending = briefed(made, request)
        uji.session.submit(request)
    end,
})
