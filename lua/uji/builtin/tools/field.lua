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
