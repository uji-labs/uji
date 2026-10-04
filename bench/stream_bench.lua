local scenario = require("scenario")

local REPLY = string.rep(scenario.REPLY, 8)
local tokens = scenario.tokens(REPLY)

scenario.open()

bench("draw each token of a 1,500 token reply", function()
    return scenario.stream(tokens)
end)

scenario.history(125)
scenario.cold()
bench("draw each token over 500 messages", function()
    return scenario.stream(tokens)
end)

scenario.serve(scenario.events(scenario.chunks(tokens)))
bench("full turn with a 1,500 token reply over HTTP", function()
    scenario.turn("why does the parser stall?")
end)
