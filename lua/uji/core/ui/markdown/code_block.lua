local Code = require("uji.core.ui.markdown.code")
local ito = require("ito")

return ito.view(function(props)
    local styles = ito.theme().styles
    return ito.VStack({
        props.language ~= nil and ito.Text(props.language):style(styles.dim):padding({ leading = 2 }),
        Code({ language = props.language, lines = props.lines }),
    })
end)
