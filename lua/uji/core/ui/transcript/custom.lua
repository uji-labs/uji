local event = require("uji.core.event")
local ito = require("ito")
local notices = require("uji.core.notices")

return ito.view(function(props)
    if not event.has("render_message") then
        return props.fallback
    end
    return ito.SubcomposeLayout(function(room)
        local payload = props.payload
        payload.width = room.width
        local value = event.ask("render_message", payload)
        if value == nil then
            return props.fallback
        end
        if not ito.is_view(value) then
            notices.push("render_message: a handler must return a view")
            return props.fallback
        end
        return value
    end)
end)
