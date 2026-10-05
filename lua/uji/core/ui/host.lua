local ito = require("ito")

local M = {}

M.Host = ito.Local(nil)

M.Hosted = ito.PreferenceKey({
    default = false,
    reduce = function(value, next_value)
        return value or next_value
    end,
})

return M
