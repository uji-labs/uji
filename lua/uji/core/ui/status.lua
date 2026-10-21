local app = require("uji.core.app")
local host = require("uji.core.ui.host")
local ito = require("ito")
local model = require("uji.core.model")
local sys = require("uji.sys")

local CROWDED = 80

return ito.view(function()
    local ui = host.Host.current
    local session = app.session
    if not session or ui:claims(ito.ToolbarPlacement.bottom_bar) then
        return nil
    end
    local ctx = ito.theme()
    local row = {}
    local function add(text, style)
        if #row > 0 then
            row[#row + 1] = ito.Text("  " .. ctx.symbols.separator .. "  "):style(ctx.styles.dim)
        end
        row[#row + 1] = ito.Text(text):style(style)
    end
    add(sys.os.shorten(session.directory), ctx.styles.muted)
    local current = model.current
    if current.model ~= "" then
        add(current.model, ctx.styles.accent)
    end
    if current.effort and current.effort ~= "off" then
        add(current.effort, ctx.styles.muted)
    end
    local budget = model.budget()
    local usable = budget and model.usable(budget)
    if usable and usable > 0 then
        local pct = math.floor(session:used_tokens() / usable * 100 + 0.5)
        add(string.format("context %d%%", pct), pct >= CROWDED and ctx.styles.notice or ctx.styles.muted)
    end
    return ito.HStack(row):padding({ horizontal = 1 }):height(1)
end)
