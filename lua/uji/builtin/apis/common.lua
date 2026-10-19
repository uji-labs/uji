local json = require("uji.utils.json")

local MIN_ANSWER = 1024
local MIN_BUDGET = 1024
local BUDGET = { minimal = 1024, low = 2048, medium = 8192, high = 16384 }
local ARRAY = getmetatable(uji.json.array({}))

local M = { MIN_ANSWER = MIN_ANSWER }

function M.fit_thinking(effort, max_output)
    local max_tokens = math.max(max_output, MIN_ANSWER)
    local budget = BUDGET[effort] or 0
    if budget > 0 and max_tokens <= budget then
        budget = math.min(budget, math.max(max_tokens - MIN_ANSWER, 0))
    end
    if budget < MIN_BUDGET then
        budget = 0
    end
    return max_tokens, budget
end

function M.arguments(raw)
    local value = json.object(raw)
    if type(value) == "table" and getmetatable(value) ~= ARRAY then
        return value
    end
    return {}
end

function M.map(list, shape)
    local out = uji.json.array({})
    for _, item in ipairs(list or {}) do
        out[#out + 1] = shape(item)
    end
    return out
end

function M.nonempty(list)
    if #list > 0 then
        return list
    end
end

function M.translate(messages, shapes, show)
    local out = uji.json.array({})
    local pending = {}
    local function flush()
        if #pending > 0 then
            for _, message in ipairs(show(pending)) do
                out[#out + 1] = message
            end
            pending = {}
        end
    end
    for _, item in ipairs(messages) do
        local shape = shapes[item.type]
        if shape then
            if item.type ~= "tool" then
                flush()
            end
            out[#out + 1] = shape(item)
            if show and item.type == "tool" then
                for _, image in ipairs(item.images or {}) do
                    pending[#pending + 1] = image
                end
            end
        end
    end
    flush()
    return out
end

M.SHOWN = "These are the images the tool calls above returned."

function M.parts(images, picture, text, word)
    local parts = M.map(images, picture)
    if text ~= "" or #parts == 0 then
        parts[#parts + 1] = word(text)
    end
    return parts
end

function M.system(request)
    local system = request.system or ""
    for _, item in ipairs(request.messages) do
        if item.type == "system" then
            system = system ~= "" and system .. "\n" .. item.text or item.text
        end
    end
    return system
end

function M.bearer(token)
    return token and "Bearer " .. token
end

function M.session(request)
    local session = request.ctx and request.ctx.session
    return session and session.id
end

local UNSUPPORTED = {
    ["$ref"] = true,
    ["$defs"] = true,
    definitions = true,
    allOf = true,
    oneOf = true,
    patternProperties = true,
    dependentSchemas = true,
    dependencies = true,
    unevaluatedProperties = true,
    propertyNames = true,
    contains = true,
    prefixItems = true,
    ["not"] = true,
    ["if"] = true,
    ["then"] = true,
    ["else"] = true,
}

local function clone(value)
    if type(value) ~= "table" or value == uji.json.null then
        return value
    end
    local meta = getmetatable(value)
    local out = type(meta) == "table" and setmetatable({}, meta) or {}
    for key, item in pairs(value) do
        out[key] = clone(item)
    end
    return out
end

local function nullable(schema)
    if schema == nil then
        return false
    end
    if schema.type == "null" then
        return true
    end
    if type(schema.type) == "table" then
        for _, name in ipairs(schema.type) do
            if name == "null" then
                return true
            end
        end
    end
    if type(schema.enum) == "table" then
        for _, value in ipairs(schema.enum) do
            if value == uji.json.null then
                return true
            end
        end
    end
    if type(schema.anyOf) == "table" then
        for _, variant in ipairs(schema.anyOf) do
            if nullable(variant) then
                return true
            end
        end
    end
    return false
end

local function strict_node(schema)
    if type(schema) ~= "table" then
        return false
    end
    for key in pairs(UNSUPPORTED) do
        if schema[key] ~= nil then
            return false
        end
    end
    if schema.anyOf then
        for _, variant in ipairs(schema.anyOf) do
            if variant.type == "object" or variant.type == "array" or variant.properties or variant.items then
                return false
            end
            if not strict_node(variant) then
                return false
            end
        end
    end
    if schema.items then
        if schema.items[1] ~= nil or not strict_node(schema.items) then
            return false
        end
    end
    if schema.type ~= "object" then
        return schema.properties == nil
    end
    if schema.additionalProperties ~= nil and schema.additionalProperties ~= false then
        return false
    end
    local required = {}
    for _, name in ipairs(schema.required or {}) do
        required[name] = true
    end
    local names = {}
    for name, property in pairs(schema.properties or {}) do
        if not strict_node(property) then
            return false
        end
        names[#names + 1] = name
        if not required[name] and not nullable(property) then
            schema.properties[name] = { anyOf = { property, { type = "null" } } }
        end
    end
    table.sort(names)
    schema.required = #names > 0 and names or uji.json.array({})
    schema.additionalProperties = false
    return true
end

function M.strict(parameters)
    if type(parameters) ~= "table" or parameters.type ~= "object" then
        return nil
    end
    local schema = clone(parameters)
    if not strict_node(schema) then
        return nil
    end
    return schema
end

return M
