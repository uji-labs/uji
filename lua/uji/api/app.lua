local config = require("uji.core.config")
local ui = require("uji.core.ui")

uji.quit = function()
    ui:quit()
end

uji.reload = config.reload
