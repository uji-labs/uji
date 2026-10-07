local process = require("uji.core.system.process")
local sys = require("uji.sys")

local M = {}

function M.eventually(check)
    for _ = 1, 150 do
        if check() then
            return
        end
        sys.sleep(0.02)
    end
    error("timed out waiting", 2)
end

function M.alive(pid)
    return process.run({ argv = { "kill", "-0", tostring(pid) } }, function() end).code == 0
end

return M
