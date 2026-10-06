local text = require("ito").text

uji.command.add("diagnostics", {
    desc = "show the errors uji ran into",
    handler = function()
        local entries = uji.diagnostics.list()
        if #entries == 0 then
            uji.notify("no diagnostics yet")
            return
        end
        local items, chosen = {}, {}
        for index, entry in ipairs(entries) do
            items[index] = entry.time .. "  " .. entry.source .. "  " .. (text.lines(entry.text)[1] or "")
            chosen[items[index]] = entry
        end
        uji.ui.pick({
            title = "Diagnostics",
            items = items,
            preview = function(item)
                return text.lines(chosen[item].text)
            end,
        })
    end,
})
