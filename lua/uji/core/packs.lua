local notices = require("uji.core.notices")
local paths = require("uji.core.paths")
local sys = require("uji.sys")
local tables = require("uji.core.tables")

local CACHE = "overrides.json"

local M = { roots = {} }

local function run_git(cwd, args)
    local command = { "git" }
    for _, arg in ipairs(args) do
        command[#command + 1] = arg
    end
    local proc, err = sys.proc.spawn(command, { cwd = cwd })
    if not proc then
        return nil, "git " .. table.concat(args, " ") .. ": " .. tostring(err)
    end
    proc:close()
    local out, errs = {}, {}
    for line, stream in proc:lines() do
        if stream == "stderr" then
            errs[#errs + 1] = line
        else
            out[#out + 1] = line
        end
    end
    local exit = proc:wait()
    local stdout = table.concat(out, "\n"):match("^%s*(.-)%s*$")
    if exit.success then
        return stdout
    end
    local detail = table.concat(errs, "\n"):match("^%s*(.-)%s*$")
    if detail == "" then
        detail = stdout
    end
    return nil, "git " .. table.concat(args, " ") .. ": " .. detail
end

local function clone(url, dir, reference)
    if reference then
        local _, err = run_git(nil, { "clone", url, dir })
        if err then
            return nil, err
        end
        return run_git(dir, { "checkout", "--detach", reference })
    end
    return run_git(nil, { "clone", "--depth", "1", url, dir })
end

local function remote_target(dir, reference)
    if not reference then
        local found = run_git(dir, { "rev-parse", "--abbrev-ref", "origin/HEAD" })
        if found then
            return found
        end
        return run_git(dir, { "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
    end
    local remote = "origin/" .. reference
    if run_git(dir, { "rev-parse", "--verify", "--quiet", remote .. "^{commit}" }) then
        return remote
    end
    return reference
end

local function update_one(dir, reference)
    local _, err = run_git(dir, { "fetch", "--tags", "--force", "origin" })
    if err then
        return nil, err
    end
    local target, problem = remote_target(dir, reference)
    if not target then
        return nil, problem
    end
    _, err = run_git(dir, { "reset", "--hard", target })
    if err then
        return nil, err
    end
    return run_git(dir, { "rev-parse", "HEAD" })
end

local function lock_path()
    local config = paths.config()
    return config and config .. "/uji-lock.json"
end

local function load_lock()
    local path = lock_path()
    local text = path and sys.fs.read(path)
    if not text then
        return {}
    end
    local ok, lock = pcall(sys.json.decode, text, { nulls = false })
    return ok and type(lock) == "table" and lock or {}
end

local function quote(value)
    return sys.json.encode(value)
end

local function save_lock(lock)
    local path = lock_path()
    if not path then
        return nil, "$HOME is not set"
    end
    local names = tables.keys(lock)
    local blocks = {}
    for index, name in ipairs(names) do
        local entry = lock[name]
        local fields = { '    "url": ' .. quote(entry.url), '    "rev": ' .. quote(entry.rev) }
        if entry.reference then
            fields[#fields + 1] = '    "reference": ' .. quote(entry.reference)
        end
        blocks[index] = "  " .. quote(name) .. ": {\n" .. table.concat(fields, ",\n") .. "\n  }"
    end
    local text = #blocks == 0 and "{}" or "{\n" .. table.concat(blocks, ",\n") .. "\n}"
    sys.fs.mkdir(sys.fs.parent(path))
    return sys.fs.write(path, text)
end

local function repo_name(url)
    local trimmed = url:gsub("/+$", ""):gsub("%.git$", "")
    if sys.fs.absolute(trimmed) then
        return sys.fs.name(trimmed) or url
    end
    return trimmed:match("([^/:]+)$") or url
end

local function expand_url(short)
    local first = short:sub(1, 1)
    local looks_local = sys.fs.absolute(short) or first == "." or first == "~"
    if short:find("://", 1, true) or short:sub(1, 4) == "git@" or looks_local then
        return paths.expand(short)
    end
    local _, slashes = short:gsub("/", "")
    if slashes == 1 then
        return "https://github.com/" .. short
    end
    return short
end

local function spec(value)
    if type(value) == "string" then
        local url = expand_url(value)
        return { name = repo_name(url), url = url }
    end
    if type(value) ~= "table" then
        return nil, "pack spec must be a string or a table"
    end
    if value.dir then
        return { name = value.name or repo_name(value.dir), dir = paths.expand(value.dir) }
    end
    local url = value.url or value[1]
    if not url then
        return nil, 'pack spec needs a url, a "user/repo" shorthand, or dir'
    end
    url = expand_url(url)
    return {
        name = value.name or repo_name(url),
        url = url,
        reference = value.commit or value.tag or value.branch,
    }
end

local function is_dir(path)
    local stat = sys.fs.stat(path)
    return stat ~= nil and stat.type == "dir"
end

local function install(found)
    if found.dir then
        if not is_dir(found.dir) then
            return nil, found.dir .. ": no such directory"
        end
        return found.dir
    end
    local site = paths.site()
    if not site then
        return nil, "$HOME is not set"
    end
    local dir = sys.fs.join(site, found.name)
    if is_dir(dir) then
        return dir
    end
    local lock = load_lock()
    local pinned = found.reference or (lock[found.name] and lock[found.name].rev)
    sys.fs.mkdir(site)
    local _, err = clone(found.url, dir, pinned)
    if err then
        return nil, err
    end
    local rev, problem = run_git(dir, { "rev-parse", "HEAD" })
    if not rev then
        return nil, problem
    end
    lock[found.name] = { url = found.url, rev = rev, reference = found.reference }
    local saved, failure = save_lock(lock)
    if not saved then
        return nil, failure
    end
    notices.push("pack: installed " .. found.name)
    return dir
end

function M.add_root(dir)
    for _, root in ipairs(M.roots) do
        if root == dir then
            return
        end
    end
    M.roots[#M.roots + 1] = dir
    local natives = sys.fs.join(dir, paths.NATIVE_DIR, "?." .. sys.os.library)
    package.cpath = package.cpath == "" and natives or package.cpath .. ";" .. natives
end

function M.add(specs)
    local count = 0
    for _ in pairs(type(specs) == "table" and specs or {}) do
        count = count + 1
    end
    if type(specs) ~= "table" or count ~= #specs then
        error('uji.pack.add takes a list of packs, for example { "user/repo" }', 2)
    end
    for _, value in ipairs(specs) do
        local found, err = spec(value)
        if not found then
            error(err, 2)
        end
        local dir, problem = install(found)
        if dir then
            M.add_root(dir)
        else
            notices.push("pack: " .. found.name .. ": " .. tostring(problem))
        end
    end
end

function M.list()
    local out = {}
    for index, root in ipairs(M.roots) do
        out[index] = root
    end
    return out
end

function M.update()
    local lock = load_lock()
    local site = paths.site()
    if not site then
        notices.push("pack: $HOME is not set")
        return
    end
    local names = tables.keys(lock)
    if #names == 0 then
        notices.push("pack: nothing installed")
        return
    end
    local changed = false
    for _, name in ipairs(names) do
        local entry = lock[name]
        local dir = sys.fs.join(site, name)
        if not is_dir(dir) then
            notices.push("pack: " .. name .. " is not installed")
        else
            local rev, err = update_one(dir, entry.reference)
            if not rev then
                notices.push("pack: " .. name .. ": " .. tostring(err))
            elseif rev == entry.rev then
                notices.push("pack: " .. name .. " already current")
            else
                notices.push("pack: updated " .. name)
                entry.rev = rev
                changed = true
            end
        end
    end
    if changed then
        local saved, err = save_lock(lock)
        if not saved then
            notices.push("pack: " .. tostring(err))
        end
    end
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local text = file:read("*a")
    file:close()
    return text
end

function M.searcher(module)
    local relative = module:gsub("%.", "/")
    local tried = {}
    for _, root in ipairs(M.roots) do
        for _, file in ipairs({ relative .. ".lua", relative .. "/init.lua" }) do
            local path = sys.fs.join(root, paths.MODULE_DIR, file)
            local source = read_file(path)
            if source then
                local chunk, err = load(source, "@" .. path)
                if not chunk then
                    error(err, 0)
                end
                return chunk, path
            end
            tried[#tried + 1] = "\n\tno file '" .. path .. "'"
        end
    end
    return table.concat(tried)
end

function M.overriding(roots)
    local out = {}
    for _, root in ipairs(roots) do
        if is_dir(sys.fs.join(root, paths.MODULE_DIR, "uji")) or is_dir(sys.fs.join(root, paths.NATIVE_DIR, "uji")) then
            out[#out + 1] = root
        end
    end
    return out
end

local function cache_path()
    local data = paths.data()
    return data and sys.fs.join(data, CACHE)
end

function M.remembered()
    local path = cache_path()
    local text = path and sys.fs.read(path)
    local ok, roots = pcall(sys.json.decode, text or "[]", { nulls = false })
    return ok and type(roots) == "table" and roots or {}
end

function M.remember(roots)
    local path = cache_path()
    if not path or tables.same(roots, M.remembered()) then
        return
    end
    sys.fs.mkdir(sys.fs.parent(path))
    sys.fs.write(path, sys.json.encode(sys.json.array(tables.copy(roots))))
end

function M.expected()
    local roots = {}
    local config = paths.config()
    if config then
        roots[1] = config
    end
    for _, root in ipairs(M.remembered()) do
        if root ~= config then
            roots[#roots + 1] = root
        end
    end
    return M.overriding(roots)
end

function M.plugin_files(root)
    local entries = sys.fs.list(sys.fs.join(root, paths.PLUGIN_DIR))
    local files = {}
    for _, entry in ipairs(entries or {}) do
        if entry.name:match("%.lua$") then
            files[#files + 1] = sys.fs.join(root, paths.PLUGIN_DIR, entry.name)
        end
    end
    table.sort(files)
    return files
end

return M
