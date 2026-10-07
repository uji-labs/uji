local ito = require("ito")
local Running = require("uji.core.ui.transcript.running")

return ito.view(function(props)
    local job = props.job
    return Running({ name = string.format(ito.theme().text.job, job.id) .. "  " .. job.command, line = job.last })
end)
