local sys = require("uji.sys")
local ui = require("uji.core.ui")

uji.diff = function(old, new, path)
    if type(old) ~= "string" or type(new) ~= "string" then
        error("uji.diff needs the old and the new text", 2)
    end
    return { path = path, changes = sys.diff(old, new, ui.theme.tokens.limits.diff_context) }
end
