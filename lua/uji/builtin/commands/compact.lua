uji.command.add("compact", {
    desc = "summarise earlier messages to free context",
    handler = function()
        local started, reason = uji.session.compact()
        if not started then
            uji.notify(reason)
        end
    end,
})
