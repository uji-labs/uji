local task = require("uji.core.task")

local M = {
    stack = {},
    loaded = {},
    order = {},
    registries = setmetatable({}, { __mode = "k" }),
    cleanups = {},
}

function M.current()
    return M.stack[#M.stack]
end

function M.track(registry)
    M.registries[registry] = true
    return registry
end

function M.on_unload(cleanup)
    local owner = M.current()
    if owner then
        M.cleanups[owner] = M.cleanups[owner] or {}
        table.insert(M.cleanups[owner], cleanup)
    end
end

function M.run(name, path, fn, ...)
    if not M.loaded[name] then
        M.order[#M.order + 1] = name
    end
    M.loaded[name] = { name = name, path = path }
    M.stack[#M.stack + 1] = name
    local results = task.pack(pcall(fn, ...))
    M.stack[#M.stack] = nil
    if not results[1] then
        error(results[2], 0)
    end
    return task.unpack(results, 2)
end

function M.source(path, name)
    local chunk, err = loadfile(path)
    if not chunk then
        error(err, 0)
    end
    return M.run(name or path, path, chunk)
end

function M.list()
    local out = {}
    for _, name in ipairs(M.order) do
        if M.loaded[name] then
            out[#out + 1] = M.loaded[name]
        end
    end
    return out
end

function M.unload(name)
    if not M.loaded[name] then
        return false
    end
    for registry in pairs(M.registries) do
        registry:drop_owner(name)
    end
    for _, cleanup in ipairs(M.cleanups[name] or {}) do
        pcall(cleanup)
    end
    M.cleanups[name] = nil
    M.loaded[name] = nil
    return true
end

function M.reload(name)
    local found = M.loaded[name]
    if not found or not found.path then
        return false
    end
    M.unload(name)
    M.source(found.path, name)
    return true
end

return M
