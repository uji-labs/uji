# telescope

A fuzzy finder.

```lua
require("telescope").setup({})
```

| Key | Action | Does |
|---|---|---|
| Ctrl+P | `telescope_find` | Opens a file in your editor. |
| Ctrl+R | `telescope_history` | Refills the input with a past message. |
| Ctrl+F | `telescope_search` | Searches file contents as you type. |

`editor` sets the program that opens files. It defaults to `UJI_EDITOR`, then
`VISUAL`, then `EDITOR`. `keys = false` leaves the keys unbound.
