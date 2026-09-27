local command = require("uji.command")
local Select = require("uji.ui.views.select")
local ui = require("uji.ui")

return function()
    local names = {}
    for index, item in ipairs(command.suggestions()) do
        names[index] = item.name
    end
    ui:ask(Select({ title = "Commands", items = names }))
end
