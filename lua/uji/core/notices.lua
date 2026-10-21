local event = require("uji.core.event")

local M = { pending = {} }

local announcing = false
local announced = 0

local function announce()
    if announcing then
        return
    end
    announcing = true
    while announced < #M.pending do
        announced = announced + 1
        local notice = M.pending[announced]
        event.emit("notice", { text = notice.text, seconds = notice.seconds, kind = notice.kind })
    end
    announcing = false
end

function M.push(message, seconds, kind)
    M.pending[#M.pending + 1] = { text = tostring(message), seconds = seconds, kind = kind }
    announce()
end

function M.take()
    local taken = M.pending
    M.pending = {}
    announced = 0
    return taken
end

return M
