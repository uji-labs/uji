local Call = require("uji.core.ui.transcript.call")
local calls = require("uji.core.ui.transcript.calls")
local ito = require("ito")

return ito.view(function(props)
    local ctx = ito.theme()
    local call = calls.describe(props.call)
    return Call({
        label = call.label or call.name,
        detail = call.detail or ctx:first(call.arguments, ctx.limits.argument_preview),
        status = props.status,
    })
end)
