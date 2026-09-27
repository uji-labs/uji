local Registry = require("uji.registry")
local notices = require("uji.notices")
local plugin = require("uji.plugin")

local RETENTIONS = { off = true, short = true, long = true }
local COMPACTION = { enabled = "boolean", reserve = "number", keep_recent = "number" }

local M = {
    functions = plugin.track(Registry(plugin.current)),
    compaction = { enabled = true, reserve = nil, keep_recent = 20000 },
    cache = "short",
}

function M.add(name, provide, opts)
    if type(name) ~= "string" or type(provide) ~= "function" then
        error("uji.context.add needs a name and a function", 2)
    end
    return M.functions:add(name, provide, opts)
end

function M.remove(name)
    return M.functions:remove(name)
end

function M.list()
    return M.functions:names()
end

function M.configure(opts)
    if type(opts) ~= "table" then
        error("uji.context.configure needs a table", 2)
    end
    for key, value in pairs(opts) do
        if key == "compaction" then
            if type(value) ~= "table" then
                error("compaction must be a table", 2)
            end
            for field, setting in pairs(value) do
                local kind = COMPACTION[field]
                if not kind then
                    error("unknown key compaction." .. tostring(field), 2)
                end
                if type(setting) ~= kind then
                    error("compaction." .. field .. " must be a " .. kind, 2)
                end
            end
            for field, setting in pairs(value) do
                M.compaction[field] = setting
            end
        elseif key == "cache" then
            if not RETENTIONS[value] then
                error("unknown variant `" .. tostring(value) .. "`, expected one of `off`, `short`, `long`", 2)
            end
            M.cache = value
        else
            error("unknown key " .. tostring(key), 2)
        end
    end
end

function M.gather(system)
    local turn = {}
    for name, provide in M.functions:each() do
        local ok, value = pcall(provide)
        if not ok then
            notices.push("context " .. name .. ": " .. tostring(value))
        else
            local text, at_turn
            if type(value) == "string" then
                text = value
            elseif type(value) == "table" then
                text = type(value.text) == "string" and value.text or ""
                at_turn = value.at == "turn"
            end
            if text and text:find("%S") then
                if at_turn then
                    turn[#turn + 1] = { type = "context", text = text }
                else
                    system = system .. "\n\n" .. text
                end
            end
        end
    end
    return system, turn
end

return M
