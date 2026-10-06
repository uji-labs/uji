local M = {}

local SEPARATORS = { [";"] = true, ["&"] = true, ["|"] = true, ["\n"] = true }
local REDIRECTS = { [">"] = true, ["<"] = true }

local function redirect(command, at)
    return REDIRECTS[command:sub(at - 1, at - 1)] or command:sub(at + 1, at + 1) == ">"
end

function M.commands(command)
    local out, current, nesting = {}, {}, {}
    local function cut()
        local piece = table.concat(current):match("^%s*(.-)[%s%$<>]*$")
        if piece ~= "" then
            out[#out + 1] = piece
        end
        current = {}
    end
    local function push(text)
        current[#current + 1] = text
    end
    local at = 1
    while at <= #command do
        local char = command:sub(at, at)
        local inside = nesting[#nesting]
        if char == "\\" then
            push(command:sub(at, at + 1))
            at = at + 1
        elseif inside == "quote" then
            if char == '"' then
                nesting[#nesting] = nil
                push(char)
            elseif char == "`" then
                cut()
                nesting[#nesting + 1] = "tick"
            elseif char == "$" and command:sub(at + 1, at + 1) == "(" then
                cut()
                nesting[#nesting + 1] = "paren"
                at = at + 1
            else
                push(char)
            end
        elseif char == "'" then
            local close = command:find("'", at + 1, true) or #command
            push(command:sub(at, close))
            at = close
        elseif char == '"' then
            nesting[#nesting + 1] = "quote"
            push(char)
        elseif char == "`" then
            cut()
            if inside == "tick" then
                nesting[#nesting] = nil
            else
                nesting[#nesting + 1] = "tick"
            end
        elseif char == "(" then
            cut()
            nesting[#nesting + 1] = "paren"
        elseif char == ")" then
            cut()
            if inside == "paren" then
                nesting[#nesting] = nil
            end
        elseif char == "&" and redirect(command, at) then
            push(char)
        elseif SEPARATORS[char] then
            cut()
        else
            push(char)
        end
        at = at + 1
    end
    cut()
    return out
end

return M
