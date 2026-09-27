local Policy = require("uji.system.policy")
local Registry = require("uji.registry")
local Roots = require("uji.system.roots")
local notices = require("uji.notices")
local paths = require("uji.paths")
local plugin = require("uji.plugin")
local sys = require("uji.sys")

local ACTIONS = { allow = true, ask = true, deny = true }

local M = {
    registry = plugin.track(Registry(plugin.current)),
    disabled = {},
    rules = {},
    changed = true,
    confined = true,
    extra = {},
}

function M.add(name, spec)
    if type(name) ~= "string" or name == "" then
        error("uji.tool.add needs a name", 2)
    end
    if type(spec) ~= "table" then
        error("uji.tool.add needs a spec table", 2)
    end
    if type(spec.run) ~= "function" then
        error("tool " .. name .. " needs a run function", 2)
    end
    local subject = spec.subject
    if subject ~= nil and type(subject) ~= "string" and type(subject) ~= "function" then
        error("subject must be a string or a function", 2)
    end
    if spec.policy ~= nil and not ACTIONS[spec.policy] then
        error("policy `" .. tostring(spec.policy) .. "` is not allow, ask or deny", 2)
    end
    if spec.display ~= nil and type(spec.display) ~= "table" then
        error("display must be a table", 2)
    end
    M.changed = true
    return M.registry:add(name, {
        name = name,
        description = spec.description or "",
        parameters = spec.parameters,
        subject = subject,
        policy = spec.policy,
        display = spec.display or {},
        run = spec.run,
    })
end

function M.remove(name)
    M.changed = true
    return M.registry:remove(name)
end

function M.get(name)
    return M.registry:get(name)
end

function M.list()
    local names = M.registry:names()
    table.sort(names)
    return names
end

function M.disable(names)
    for _, name in ipairs(names) do
        M.disabled[name] = true
    end
end

function M.enable(names)
    for _, name in ipairs(names) do
        M.disabled[name] = nil
    end
end

function M.policy(rules)
    if type(rules) ~= "table" then
        error("uji.tool.policy needs a table", 2)
    end
    for name, value in pairs(rules) do
        M.rules[name] = value
    end
    M.changed = true
end

function M.confine(enabled)
    if enabled ~= nil then
        M.confined = enabled == true
    end
    return M.confined
end

function M.roots(list)
    if list ~= nil then
        M.extra = {}
        for index, root in ipairs(list) do
            M.extra[index] = paths.expand(root)
        end
    end
    local out = {}
    for index, root in ipairs(M.extra) do
        out[index] = root
    end
    return out
end

function M.files(cwd)
    return Roots(cwd or sys.os.cwd(), M.extra, M.confined)
end

function M.compiled()
    if M.changed or not M.cached then
        local known = {}
        for _, name in ipairs(M.registry:names()) do
            known[name] = true
        end
        local compiled, problems = Policy.compile(M.rules, known)
        for _, problem in ipairs(problems) do
            notices.push(problem)
        end
        M.cached = compiled
        M.changed = false
    end
    return M.cached
end

function M.specs(only)
    local wanted
    if only then
        wanted = {}
        for _, name in ipairs(only) do
            wanted[name] = true
        end
    end
    local out = {}
    for _, name in ipairs(M.list()) do
        if not wanted or wanted[name] then
            local tool = M.get(name)
            out[#out + 1] = {
                name = name,
                description = tool.description,
                parameters = tool.parameters or sys.json.decode("{}"),
            }
        end
    end
    return out
end

function M.subject(tool, name, args)
    if tool == nil or tool.subject == nil then
        return name
    end
    if type(tool.subject) == "string" then
        return tool.subject
    end
    local value = tool.subject(args)
    return value or ""
end

function M.detail(tool, args)
    if tool == nil or tool.subject == nil then
        return nil
    end
    if type(tool.subject) == "string" then
        return tool.subject
    end
    return tool.subject(args)
end

return M
