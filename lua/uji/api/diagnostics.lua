local diagnostics = require("uji.core.diagnostics")
local task = require("uji.core.task")

uji.diagnostics = {
    list = task.callback(function()
        return diagnostics.list()
    end),
}
