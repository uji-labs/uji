# Rebuilding uji

Everything uji does, from startup to the screen, is written in Lua in the
`uji` module tree, and you can replace any file in it. A file at
`lua/uji/<path>.lua` in your config directory or in a pack replaces the
built-in module `uji.<path>`. A module that is a folder, such as
`uji.core.agent`, lives in `lua/uji/core/agent/init.lua`.

A replacement is a whole file. uji loads yours instead of the built-in one, so
the easiest start is a copy of the original from the `lua/uji` folder of the
uji source.

For example, `~/.config/uji/lua/uji/core/prompt.lua`:

```lua
local M = {}

function M.system(env)
  return "You are a careful coding agent. Work in " .. env.directory .. "."
end

return M
```
