local Registry = require("uji.core.registry")
local check = require("uji.core.check")
local notices = require("uji.core.notices")
local plugin = require("uji.core.plugin")
local sys = require("uji.sys")

local M = { commands = plugin.track(Registry(plugin.current)) }

local function parse(spec)
    if type(spec) == "function" then
        return { handler = spec, desc = "" }
    end
    if type(spec) == "table" and type(spec.handler) == "function" then
        return { handler = spec.handler, desc = spec.desc or "" }
    end
    error("uji.command.add needs a function or a table with a handler", 3)
end

function M.add(name, spec)
    check.name(name, "uji.command.add")
    return M.commands:add(name, parse(spec))
end

function M.remove(name)
    return M.commands:remove(name)
end

function M.list()
    return M.commands:sorted()
end

function M.run(line)
    local trimmed = line:match("^%s*(.-)%s*$")
    local name, rest = trimmed:match("^(%S+)%s*(.*)$")
    name = name or trimmed
    local found = M.commands:get(name)
    if not found then
        notices.push("unknown command: " .. name)
        return
    end
    local ok, err = pcall(found.handler, rest or "")
    if not ok then
        notices.push(name .. ": " .. sys.message(err))
    end
end

function M.suggestions()
    local items = {}
    for index, name in ipairs(M.list()) do
        items[index] = { name = name, desc = M.commands:get(name).desc }
    end
    return items
end

return M
