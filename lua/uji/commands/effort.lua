local model = require("uji.model")
local notices = require("uji.notices")
local Select = require("uji.ui.views.select")
local ui = require("uji.ui")

return function()
    local current = model.setting("llm.effort") or ""
    local items = {}
    for index, name in ipairs(model.EFFORTS) do
        items[index] = name == current and name .. " (current)" or name
    end
    local choice = ui:ask(Select({ title = "Reasoning effort", items = items }))
    if not choice then
        return
    end
    local name = choice:match("^(%S+)")
    for _, known in ipairs(model.EFFORTS) do
        if known == name then
            model.set_setting("llm.effort", name)
            model.resolve()
            notices.push("reasoning effort: " .. name)
            return
        end
    end
    notices.push("unknown effort")
end
