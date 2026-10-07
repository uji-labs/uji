local text = require("ito").text

uji.command.add("diagnostics", {
    desc = "show the errors uji ran into",
    handler = function()
        local entries = uji.diagnostics.list()
        if #entries == 0 then
            uji.notify("no diagnostics yet")
            return
        end
        uji.ui.pick({
            title = "Diagnostics",
            items = entries,
            label = function(entry)
                return entry.time .. "  " .. entry.source .. "  " .. (text.lines(entry.text)[1] or "")
            end,
            preview = function(entry)
                return text.lines(entry.text)
            end,
        })
    end,
})
