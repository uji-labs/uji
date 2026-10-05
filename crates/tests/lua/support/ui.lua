local keys = require("uji.core.ui.keys")
local text = require("ito").text
local ui = require("uji.core.ui")

local M = {}

function M.handle(chord)
    if ui.modal then
        ui.modal:key(chord, ui)
    else
        ui:normal_key(chord)
    end
end

function M.press(key)
    M.handle(keys.chord(key))
end

function M.typing(value)
    for char in value:gmatch(text.CHAR) do
        M.handle(keys.chord(char))
    end
end

function M.rows(fresh)
    if fresh then
        ui.screen:clear()
    end
    ui:paint()
    local _, height = ui.screen:size()
    local rows = {}
    for row = 0, height - 1 do
        rows[#rows + 1] = ui.screen:text(row)
    end
    return rows
end

function M.screen()
    return table.concat(M.rows())
end

function M.find(label)
    for row, line in ipairs(M.rows()) do
        if line:find(label, 1, true) then
            return row - 1
        end
    end
end

return M
