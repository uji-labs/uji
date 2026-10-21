local packs = require("uji.core.packs")
local paths = require("uji.core.paths")
local plugin = require("uji.core.plugin")
local sys = require("uji.sys")

local M = {}

local NAME = "^[%w_%-%.]+$"
local SKIP = { uji = true, native = true, plugin = true }

local function config()
    return paths.config()
end

local function plugin_dir()
    local root = config()
    return root and sys.fs.join(root, paths.PLUGIN_DIR)
end

local function is_file(path)
    local stat = sys.fs.stat(path)
    return stat ~= nil and stat.type == "file"
end

local function entry_at(path)
    local dir = sys.fs.parent(path)
    local name = sys.fs.name(path)
    for _, entry in ipairs(dir and sys.fs.list(dir) or {}) do
        if entry.name == name then
            return entry
        end
    end
end

local function target_path(name)
    local dir = plugin_dir()
    return dir and sys.fs.join(dir, name .. ".lua")
end

local function modules(root)
    local found = {}
    for _, entry in ipairs(sys.fs.list(sys.fs.join(root, paths.MODULE_DIR)) or {}) do
        local name = entry.name:gsub("%.lua$", "")
        local listed = (entry.type == "file" and entry.name:match("%.lua$") ~= nil)
            or (entry.type == "dir" and is_file(sys.fs.join(root, paths.MODULE_DIR, entry.name, paths.INIT_FILE)))
        if listed and not SKIP[name] then
            found[#found + 1] = name
        end
    end
    table.sort(found)
    return found
end

local function requires(text, name)
    return text:find('require("' .. name .. '")', 1, true) ~= nil or text:find("require('" .. name .. "')", 1, true) ~= nil
end

function M.enabled(name)
    if type(name) ~= "string" then
        return nil
    end
    local dir = plugin_dir()
    if dir then
        for _, entry in ipairs(sys.fs.list(dir) or {}) do
            local path = sys.fs.join(dir, entry.name)
            local text = entry.name:match("%.lua$") and sys.fs.read(path)
            if text and requires(text, name) then
                return path
            end
        end
    end
    local root = config()
    local init = root and sys.fs.join(root, paths.INIT_FILE)
    local text = init and is_file(init) and sys.fs.read(init)
    if text and requires(text, name) then
        return init
    end
end

function M.available()
    local out = {}
    for _, root in ipairs(packs.list()) do
        for _, name in ipairs(modules(root)) do
            out[#out + 1] = { name = name, root = root }
        end
    end
    return out
end

local function found(name)
    for _, listed in ipairs(M.available()) do
        if listed.name == name then
            return listed
        end
    end
end

local function literal(spec)
    if type(spec) == "string" then
        return string.format("%q", spec)
    end
    if spec.dir then
        return string.format("{ dir = %q }", spec.dir)
    end
    return string.format("{ url = %q, commit = %q }", spec.url, spec.commit)
end

local function template(name, spec)
    local lines = {}
    if spec then
        lines[#lines + 1] = "uji.pack.add({ " .. literal(spec) .. " })"
    end
    lines[#lines + 1] = string.format("require(%q).setup({})", name)
    return table.concat(lines, "\n") .. "\n"
end

local function resolve(target, opts)
    if type(target) ~= "string" or target == "" then
        return nil, "plugin add needs a name or a pack"
    end
    if opts.name and not opts.name:match(NAME) then
        return nil, "invalid plugin name: " .. tostring(opts.name)
    end
    if target:match(NAME) then
        if not found(target) then
            return nil, "no installed pack offers " .. target .. "; pass a pack instead"
        end
        return { name = target }
    end
    local spec
    if packs.is_local(target) then
        if opts.rev then
            return nil, "--rev needs a pack to clone, not a directory"
        end
        spec = { dir = target }
    elseif opts.rev then
        spec = { url = target, commit = opts.rev }
    else
        spec = target
    end
    local root, err = packs.install(spec)
    if not root then
        return nil, err
    end
    local offered = modules(root)
    if opts.name then
        for _, name in ipairs(offered) do
            if name == opts.name then
                return { name = name, spec = spec }
            end
        end
        return nil, root .. " does not offer " .. opts.name
    end
    if #offered == 1 then
        return { name = offered[1], spec = spec }
    end
    if #offered == 0 then
        return nil, root .. " is not a pack: it has no lua/ module"
    end
    return nil, "that pack offers " .. table.concat(offered, ", ") .. "; name one with --name"
end

function M.add(target, opts)
    opts = opts or {}
    local chosen, err = resolve(target, opts)
    if not chosen then
        return nil, err
    end
    local path = target_path(chosen.name)
    if not path then
        return nil, "$HOME is not set"
    end
    local at = M.enabled(chosen.name)
    if at and at ~= path then
        return nil, "enabled in " .. sys.os.shorten(at) .. "; remove it there"
    end
    local entry = entry_at(path)
    if entry and entry.type == "link" then
        return nil, path .. " is a symlink; replace it yourself"
    end
    if entry and not opts.force then
        return nil, "already enabled in " .. sys.os.shorten(path) .. "; use --force to rewrite it"
    end
    local dir = plugin_dir()
    local made, problem = sys.fs.mkdir(dir)
    if not made then
        return nil, dir .. ": " .. tostring(problem)
    end
    local written, failure = sys.fs.write(path, template(chosen.name, chosen.spec))
    if not written then
        return nil, path .. ": " .. tostring(failure)
    end
    return path
end

function M.remove(name)
    if type(name) ~= "string" or not name:match(NAME) then
        return nil, "invalid plugin name: " .. tostring(name)
    end
    local path = target_path(name)
    local entry = path and entry_at(path)
    if entry then
        if entry.type == "link" then
            return nil, path .. " is a symlink; remove it yourself"
        end
        local removed, err = sys.fs.remove(path)
        if not removed then
            return nil, path .. ": " .. tostring(err)
        end
        return path
    end
    local at = M.enabled(name)
    if at then
        return nil, "enabled in " .. sys.os.shorten(at) .. "; remove it there"
    end
    return nil, "no plugin file enables " .. name
end

function M.lines()
    local out = {}
    for _, listed in ipairs(M.available()) do
        local state = M.enabled(listed.name) and "on" or "off"
        local line = string.format("%-20s %-3s %s", listed.name, state, sys.os.shorten(listed.root))
        local reason = plugin.deprecation(listed.name)
        if reason ~= nil then
            line = line .. "  deprecated"
            if reason ~= "" then
                line = line .. ": " .. reason
            end
        end
        out[#out + 1] = line
    end
    return out
end

function M.cli(parsed)
    local sub = parsed.positional and parsed.positional[1]
    if sub == "list" then
        return M.lines()
    end
    local target = parsed.positional and parsed.positional[2]
    if sub == "add" then
        if not target then
            return nil, "plugin add needs a name or a pack"
        end
        local path, err = M.add(target, { name = parsed.flags.name, rev = parsed.flags.rev, force = parsed.flags.force })
        return path and { path } or nil, err
    end
    if sub == "remove" then
        if not target then
            return nil, "plugin remove needs a name"
        end
        local path, err = M.remove(target)
        return path and { path } or nil, err
    end
    return nil, "plugin needs list, add <name|pack> or remove <name>"
end

return M
