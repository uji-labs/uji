uji.command.add("effort", {
    desc = "how hard the model should think",
    handler = function()
        local available = uji.model.efforts()
        if #available == 0 then
            uji.notify("this model has no reasoning effort to set")
            return
        end
        local current = uji.model.current().effort
        local items, efforts = {}, {}
        for _, name in ipairs(available) do
            local label = name == current and name .. " (current)" or name
            items[#items + 1] = label
            efforts[label] = name
        end
        local choice = uji.ui.select({ title = "Reasoning effort", items = items })
        if not choice then
            return
        end
        uji.model.use({ effort = efforts[choice] })
        uji.notify("reasoning effort: " .. efforts[choice])
    end,
})
