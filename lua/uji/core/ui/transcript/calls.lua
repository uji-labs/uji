local notices = require("uji.core.notices")
local sys = require("uji.sys")
local tool = require("uji.core.tool")

local M = {}

function M.describe(call)
    local found = { name = call.name, arguments = call.arguments or "" }
    local entry = tool.get(call.name)
    local ok, args = pcall(sys.json.decode, call.arguments or "", { nulls = false })
    if entry and ok and type(args) == "table" then
        local fine, detail = pcall(tool.detail, entry, args)
        if not fine then
            notices.push(call.name .. " subject: " .. sys.message(detail))
            detail = nil
        end
        found.verb = entry.display and entry.display.verb
        found.detail = detail
    end
    return found
end

return M
