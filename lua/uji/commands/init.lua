local command = require("uji.command")

local BUILTINS = {
    { "login", "configure provider and auth" },
    { "models", "pick the default model" },
    { "reload", "reload config and plugins" },
    { "effort", "how hard the model should think" },
    { "thinking", "show or hide model reasoning" },
    { "compact", "summarise earlier messages to free context" },
    { "sync", "update installed packs" },
    { "quit", "leave uji" },
    { "help", "list commands" },
}

for _, builtin in ipairs(BUILTINS) do
    command.builtin(builtin[1], builtin[2], require("uji.commands." .. builtin[1]))
end
