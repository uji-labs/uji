<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/readme-header-dark.png">
  <img src="images/readme-header-light.png" width="640" alt="uji. A coding agent you can shape with Lua.">
</picture>

# Introduction

uji is a coding agent for your terminal, configured in Lua. This is a
complete `~/.config/uji/init.lua`:

```lua
require("uji.builtin.defaults")

uji.pack.add({ "uji-labs/uji-plugins" })
require("statusline").setup({})
require("planmode").setup({})

uji.tool.policy({
  run_command = { allow = { "git status", "cargo test*" } },
})

uji.keymap.add("normal", "<C-p>", { command = "models" })

uji.command.add("standup", function()
  uji.session.submit("Summarise the commits since yesterday.")
end)
```

- [Getting started](getting-started/index.md) installs uji and signs you in.
- [Configuration](configuration/index.md) shows where your config goes.
- [Plugins](plugins/index.md) lists the plugins and their options.
- [Examples](examples/index.md) build tools, commands, a footer, providers and approval rules.
- [Rebuilding uji](rebuilding/index.md) replaces any part of uji with your own Lua.
- [API reference](api/index.md) lists every `uji.*` function.
- [Runtime](runtime/index.md) covers tasks, the network, processes, storage and the system.
