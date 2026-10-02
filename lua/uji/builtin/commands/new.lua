uji.command.add("new", {
    desc = "start a new session",
    handler = function()
        require("uji.core.ui.sessions").restart(nil, true)
    end,
})
