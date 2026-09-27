local Registry = require("uji.registry")
local notices = require("uji.notices")
local plugin = require("uji.plugin")

local M = {
    builtins = Registry(),
    commands = plugin.track(Registry(plugin.current)),
}

local function parse(spec)
    if type(spec) == "function" then
        return { handler = spec, desc = "", force = false }
    end
    if type(spec) == "table" and type(spec.handler) == "function" then
        return { handler = spec.handler, desc = spec.desc or "", force = spec.force == true }
    end
    error("uji.command.add needs a function or a table with a handler", 3)
end

function M.builtin(name, desc, handler)
    M.builtins:add(name, { handler = handler, desc = desc })
end

function M.add(name, spec)
    if type(name) ~= "string" or name == "" then
        error("uji.command.add needs a name", 2)
    end
    return M.commands:add(name, parse(spec))
end

function M.remove(name)
    return M.commands:remove(name)
end

function M.list()
    local names = M.commands:names()
    table.sort(names)
    return names
end

function M.resolve(name)
    local lua = M.commands:get(name)
    if lua and lua.force then
        return lua
    end
    return M.builtins:get(name) or lua
end

function M.run(line)
    local trimmed = line:match("^%s*(.-)%s*$")
    local name, rest = trimmed:match("^(%S+)%s*(.*)$")
    name = name or trimmed
    local found = M.resolve(name)
    if not found then
        notices.push("unknown command: " .. name)
        return
    end
    local ok, err = pcall(found.handler, rest or "")
    if not ok then
        notices.push(name .. ": " .. tostring(err))
    end
end

function M.suggestions()
    local items = {}
    for name, builtin in M.builtins:each() do
        local lua = M.commands:get(name)
        local desc = builtin.desc
        if lua and lua.force and lua.desc ~= "" then
            desc = lua.desc
        end
        items[#items + 1] = { name = name, desc = desc }
    end
    for _, name in ipairs(M.list()) do
        if not M.builtins:get(name) then
            local lua = M.commands:get(name)
            items[#items + 1] = { name = name, desc = lua.desc ~= "" and lua.desc or "lua command" }
        end
    end
    return items
end

return M
