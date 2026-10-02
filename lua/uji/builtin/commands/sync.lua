uji.command.add("sync", {
    desc = "update installed packs",
    handler = function()
        uji.pack.update()
        uji.reload()
    end,
})
