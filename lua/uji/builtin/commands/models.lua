uji.command.add("models", {
    desc = "pick the default model",
    handler = function()
        local now = uji.model.current()
        local available = {}
        for _, provider in ipairs(uji.provider.list()) do
            if provider.id == now.provider or uji.auth.authenticated(provider.id) then
                local row = uji.provider.load(provider.id)
                if row.error then
                    uji.notify("could not load " .. row.name .. " models: " .. row.error)
                end
                if #row.models > 0 then
                    available[#available + 1] = row
                end
            end
        end
        if #available == 0 then
            uji.notify("Please run /login to configure a provider")
            return
        end
        local qualify = #available > 1
        local items, choices, current = {}, {}, nil
        for _, provider in ipairs(available) do
            for _, entry in ipairs(provider.models) do
                local label = qualify and provider.name .. " · " .. entry.id or entry.id
                choices[label] = { provider = provider.id, model = entry.id }
                items[#items + 1] = label
                if provider.id == now.provider and entry.id == now.model then
                    current = label
                end
            end
        end
        local title = qualify and "Models" or available[1].name .. " models"
        local choice = uji.ui.select({ title = title, items = items, current = current })
        local picked = choice and choices[choice]
        if picked then
            uji.model.use(picked)
        end
    end,
})
