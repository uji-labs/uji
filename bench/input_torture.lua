local scenario = require("scenario")
local screen = require("support.ui")
local ui = require("uji.core.ui")

scenario.open()

torture("paste 5 MB", function()
    ui:paste(string.rep("let tail = String::with_capacity(CHUNK);\n", 125000))
    ui:render()
    ui:clear_input()
    ui:render()
end)

torture("a key in a 10,000 line draft", function()
    ui:set_input(string.rep("refactor the tokenizer so it streams\n", 10000))
    ui:render()
    screen.press("a")
    ui:render()
    ui:clear_input()
end)

torture("type 2,000 keys with a frame each", function()
    for _ = 1, 2000 do
        screen.press("a")
        ui:render()
    end
    ui:clear_input()
end, { budget = 5 })

torture("move up through a 2,000 line draft", function()
    ui:set_input(string.rep("a line of the draft\n", 2000))
    for _ = 1, 2000 do
        screen.press("up")
        ui:render()
    end
    ui:clear_input()
end, { budget = 5 })

torture("type 2,000 wide and combining characters", function()
    local text = require("uji.core.ui.text")
    local wide = text.chars(string.rep("世🚀é̃👩‍👩‍👧", 400))
    for index = 1, 2000 do
        screen.typing(wide[(index - 1) % #wide + 1])
        ui:render()
    end
    ui:clear_input()
end, { budget = 5 })
