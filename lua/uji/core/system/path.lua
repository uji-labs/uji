local M = {}

function M.absolute(path)
    return path:sub(1, 1) == "/"
end

function M.parts(path)
    local out = {}
    for part in path:gmatch("[^/]+") do
        out[#out + 1] = part
    end
    return out
end

function M.join(base, rest)
    if rest == nil or rest == "" or rest == "." then
        return base
    end
    if M.absolute(rest) then
        return rest
    end
    if base:sub(-1) == "/" then
        return base .. rest
    end
    return base .. "/" .. rest
end

function M.normalize(path)
    local out = {}
    for _, part in ipairs(M.parts(path)) do
        if part == ".." then
            if #out > 0 then
                out[#out] = nil
            end
        elseif part ~= "." then
            out[#out + 1] = part
        end
    end
    local joined = table.concat(out, "/")
    if M.absolute(path) then
        return "/" .. joined
    end
    return joined == "" and "." or joined
end

function M.stays_within(path)
    local depth = 0
    for _, part in ipairs(M.parts(path)) do
        if part == ".." then
            depth = depth - 1
        elseif part ~= "." then
            depth = depth + 1
        end
        if depth < 0 then
            return false
        end
    end
    return true
end

function M.strip_prefix(path, root)
    local normalized_root = M.normalize(root)
    local normalized = M.normalize(path)
    if normalized == normalized_root then
        return "."
    end
    local prefix = normalized_root == "/" and "/" or normalized_root .. "/"
    if normalized:sub(1, #prefix) == prefix then
        return normalized:sub(#prefix + 1)
    end
end

function M.within(path, root)
    return M.strip_prefix(path, root) ~= nil
end

function M.parent(path)
    local parent = path:match("^(.*)/[^/]*$")
    if parent == "" then
        return "/"
    end
    return parent
end

function M.base(path)
    return path:match("([^/]*)$")
end

return M
