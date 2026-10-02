local app = require("uji.core.app")
local notices = require("uji.core.notices")
local sessions = require("uji.core.ui.sessions")
local ui = require("uji.core.ui")

uji.command.add("sessions", {
    desc = "resume or delete sessions in this directory",
    handler = function()
        if sessions.busy() then
            notices.push("resolve pending work and queued messages before opening sessions")
            return
        end
        local chosen = ui:ask(sessions.Picker(app.store, app.session.directory, app.session.id))
        if chosen then sessions.switch(chosen) end
    end,
})
