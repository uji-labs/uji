local config = require("uji.config")
local packs = require("uji.packs")

return function()
    packs.update()
    config.reload()
end
