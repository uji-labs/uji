uji.command.add("compact", {
    desc = "summarise earlier messages to free context",
    handler = function()
        if not uji.session.compact() then
            uji.notify("nothing to compact yet")
        end
    end,
})
