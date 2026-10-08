local ito = require("ito")
local ToolOutput = require("uji.core.ui.transcript.tool_output")
local Wrapped = require("uji.core.ui.transcript.wrapped")

return ito.view(function(props)
    local ctx = ito.theme()
    local header = ctx.symbols.shell .. " " .. props.command
    if props.code ~= 0 then
        header = header .. "  (" .. ctx.text.exit .. " " .. tostring(props.code) .. ")"
    end
    local rows = { Wrapped({ text = header, style = ctx.styles.accent }) }
    if props.output ~= "" then
        rows[2] = ToolOutput({
            content = props.output,
            failed = props.failed,
            expanded = props.expanded,
            toggle = props.toggle,
        })
    end
    return ito.VStack(rows)
end)
