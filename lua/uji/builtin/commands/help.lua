uji.command.add("help", {
    desc = "list commands",
    handler = function()
        uji.ui.select({ title = "Commands", items = uji.command.list() })
    end,
})
