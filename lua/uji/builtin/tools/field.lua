local tables = require("uji.core.tables")

local LISTED = 20

local M = {}

function M.text(args, key)
    local value = args[key]
    return type(value) == "string" and value or ""
end

function M.count(args, key)
    local value = args[key]
    if type(value) == "number" and value >= 0 and value % 1 == 0 then
        return value
    end
end

function M.resolve(args)
    local value = M.text(args, "path")
    if not value:find("*", 1, true) then
        return args
    end
    local found, err = uji.fs.glob((value:gsub("[%?%[%]]", "[%0]")))
    if not found then
        return nil, "error: " .. err
    end
    if #found == 0 then
        return nil, "error: no file matches " .. value
    end
    if #found > 1 then
        local shown = table.concat({ unpack(found, 1, LISTED) }, "\n")
        local more = #found > LISTED and string.format("\nand %d more", #found - LISTED) or ""
        return nil, string.format("error: %s matches %d files; name one of them:\n%s%s", value, #found, shown, more)
    end
    return tables.with(args, "path", found[1])
end

function M.subject(key)
    return function(args)
        return M.text(args, key)
    end
end

function M.missing(args, ...)
    for _, key in ipairs({ ... }) do
        if M.text(args, key) == "" then
            return "error: `" .. key .. "` is required and must be a non-empty string"
        end
    end
end

return M
