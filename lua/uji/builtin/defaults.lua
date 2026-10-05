uji.tool.policy({
    run_command = {
        deny = { "/^rm\\s+-rf/" },
    },
})

uji.keymap.add("normal", "<A-e>", { command = "effort" })
