local Policy = require("uji.core.system.policy")
local Registry = require("uji.core.registry")
local Roots = require("uji.core.system.roots")
local app = require("uji.core.app")
local check = require("uji.core.check")
local notices = require("uji.core.notices")
local paths = require("uji.core.paths")
local plugin = require("uji.core.plugin")
local sys = require("uji.sys")

local ACTIONS = { allow = true, ask = true, deny = true }

local M = {
    registry = plugin.track(Registry(plugin.current)),
    displays = plugin.track(Registry(plugin.current)),
    disabled = {},
    rules = {},
    confined = true,
    extra = {},
}

function M.add(name, spec)
    check.name(name, "uji.tool.add")
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
    return M.registry:remove(name)
end

function M.get(name)
    return M.registry:get(name)
end

function M.display(name, opts)
    check.name(name, "uji.tool.display")
    check.options(opts, "uji.tool.display")
    return M.displays:add(name, {
        name = name,
        subject = opts.subject,
        display = { verb = opts.verb, question = opts.question, preview = opts.preview },
    })
end

function M.described(name)
    return M.registry:get(name) or M.displays:get(name)
end

function M.list()
    return M.registry:sorted()
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
    M.cached = nil
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

function M.workspace()
    return M.files(app.directory())
end

function M.compiled()
    if not M.cached then
        local compiled, problems = Policy.compile(M.rules)
        for _, problem in ipairs(problems) do
            notices.push(problem)
        end
        M.cached = compiled
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

function M.detail(tool, args)
    if tool == nil or tool.subject == nil then
        return nil
    end
    if type(tool.subject) == "string" then
        return tool.subject
    end
    return tool.subject(args)
end

function M.subject(tool, name, args)
    if tool == nil or tool.subject == nil then
        return name
    end
    return M.detail(tool, args) or ""
end

return M
