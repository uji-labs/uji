local sys = require("uji.sys")

local M = {}

local VARIANTS = { "8", "9", "a", "b" }

local function hex(bytes)
    return (bytes:gsub(".", function(char)
        return string.format("%02x", char:byte())
    end))
end

function M.new()
    local time = string.format("%012x", sys.os.now())
    local noise = hex(sys.random(10))
    local variant = VARIANTS[(noise:byte(4) % 4) + 1]
    return table.concat({
        time:sub(1, 8),
        "-",
        time:sub(9, 12),
        "-7",
        noise:sub(1, 3),
        "-",
        variant,
        noise:sub(5, 7),
        "-",
        noise:sub(8, 19),
    })
end

return M
