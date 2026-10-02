# Quitting and reloading

## uji.quit()

Fires [`before_quit`](events.md#before_quit), restores the terminal and exits
uji. `/quit` calls this.

```lua
uji.keymap.add("normal", "<C-q>", function()
  uji.quit()
end)
```

## uji.reload()

Restarts uji on the same session, reading your config and plugins again, and
keeps the text on the input line. While a turn runs, uji doesn't restart and
says so in a notice. `/reload` calls this.

```lua
uji.keymap.add("normal", "<A-r>", function()
  uji.reload()
end)
```
