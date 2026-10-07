local M = {}

function M.count(number, word)
    return number .. " " .. word .. (number == 1 and "" or "s")
end

return M
