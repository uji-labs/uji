local ito = require("ito")

return ito.view(function(props)
    local code = ito.theme().styles.code
    local rows = {}
    for index, line in ipairs(props.lines) do
        rows[index] = { { "  " .. line, code } }
    end
    return ito.Lines(rows)
end)
