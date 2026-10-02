local sys = require("uji.sys")

local M = {}

local ARRAY = debug.getmetatable(sys.json.array({}))

local function shape(value)
    if type(value) ~= "table" then
        return type(value)
    end
    return debug.getmetatable(value) == ARRAY and "array" or "object"
end

local function show(value)
    if value == nil then
        return "nothing"
    end
    local ok, text = pcall(sys.json.encode, value)
    return ok and text or tostring(value)
end

function M.canonical(value)
    return sys.json.decode(sys.json.encode(value))
end

function M.normalize(value)
    if type(value) ~= "table" then
        return value
    end
    local out = shape(value) == "array" and sys.json.array({}) or {}
    for key, item in pairs(value) do
        if key == "arguments" and type(item) == "string" then
            local ok, parsed = pcall(sys.json.decode, item)
            out[key] = ok and parsed or item
        else
            out[key] = M.normalize(item)
        end
    end
    return out
end

function M.diff(want, got, path)
    path = path or "$"
    if shape(want) ~= shape(got) or (type(want) ~= "table" and want ~= got) then
        return string.format("%s: expected %s, got %s", path, show(want), show(got))
    end
    if type(want) ~= "table" then
        return nil
    end
    for key, value in pairs(want) do
        local problem = M.diff(value, got[key], path .. "." .. tostring(key))
        if problem then
            return problem
        end
    end
    for key, value in pairs(got) do
        if want[key] == nil then
            return string.format("%s.%s: unexpected %s", path, tostring(key), show(value))
        end
    end
end

return M
