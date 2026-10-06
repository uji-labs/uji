uji.command.add("effort", {
    desc = "how hard the model should think",
    handler = function()
        local available = uji.model.efforts()
        if #available == 0 then
            uji.notify("this model has no reasoning effort to set")
            return
        end
        local choice = uji.ui.select({ title = "Reasoning effort", items = available, current = uji.model.current().effort })
        if not choice then
            return
        end
        uji.model.use({ effort = choice })
        uji.notify("reasoning effort: " .. choice)
    end,
})
