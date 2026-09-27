local app = require("uji.app")
local notices = require("uji.notices")

return function()
    if not app.agent:compact(app.agent:keep_recent_now()) then
        notices.push("nothing to compact yet")
    end
end
