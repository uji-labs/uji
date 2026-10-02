local sys = require("uji.sys")

local M = {}

function M.attach(session)
    M.session = session
    M.agent = require("uji.core.agent")(session)
    return M.agent
end

function M.directory()
    return M.session and M.session.directory or sys.os.cwd()
end

return M
