local scenario = require("scenario")
local screen = require("support.ui")
local ui = require("uji.core.ui")

local DRAFT = string.rep("refactor the tokenizer so it streams chunks ", 120)
local PASTE = string.rep("fn tokens(source: &str) -> impl Iterator<Item = &str> { source.split(' ') }\n", 1400)

scenario.open()

local function keystroke()
    screen.press("a")
    ui:render()
    screen.press("backspace")
    ui:render()
    return 2
end

bench("key into an empty draft", keystroke)

ui:set_input(DRAFT)
bench("key into a 5,000 character draft", keystroke)
ui:clear_input()

scenario.history(125)
scenario.cold()
bench("key with 500 messages on screen", keystroke)

bench("paste 100 KB", function()
    ui:paste(PASTE)
    ui:render()
    ui:clear_input()
    ui:render()
    return 2
end)
