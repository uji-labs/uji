local event = require("uji.event")

local M = { pending = {} }

function M.push(message)
    message = tostring(message)
    M.pending[#M.pending + 1] = message
    event.emit("notice", { text = message })
end

function M.take()
    local taken = M.pending
    M.pending = {}
    return taken
end

event.report = M.push

return M
