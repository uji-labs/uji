# uji.keymap

A binding belongs to one of six modes.

| Mode | Where it applies |
|---|---|
| `normal` | The input line. |
| `suggest` | The command list that opens when you type `/`. |
| `select` | Pickers and lists. |
| `prompt` | Text prompts. |
| `confirm` | The approval question. |
| `overlay` | An [overlay](ui.md#ujiuioverlaycontent-opts) on top. |

A key is a single character such as `"q"`, or a chord in angle brackets.
`<C-x>` is Ctrl, `<A-x>` or `<M-x>` is Alt, `<S-x>` is Shift, and they
combine, as in `<C-A-x>`. The named keys are `CR`, `Esc`, `BS`, `Del`, `Tab`,
`S-Tab`, `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `PageUp`, `PageDown`,
`Insert`, `Space`, `lt` for `<`, `gt` for `>`, and `F1` to `F12`.

## uji.keymap.add(mode, key, binding)

Binds a key in one mode, replacing what the key did there.

| Argument | Type | Meaning |
|---|---|---|
| `mode` | string | One of the six modes. |
| `key` | string | A key or chord. |
| `binding` | string, table or function | An action name from the list below, `{ command = "name" }` to run a slash command, or a function. |

Raises an error for an unknown mode, a key uji cannot parse, or a binding of
another type.

```lua
uji.keymap.add("normal", "<C-p>", { command = "models" })
uji.keymap.add("normal", "<C-l>", "clear_input")
uji.keymap.add("normal", "<A-i>", function()
  uji.session.interrupt()
end)
```

## uji.keymap.remove(mode, key)

Unbinds a key in one mode, including a default binding.

```lua
uji.keymap.remove("normal", "<C-t>")
```

## uji.keymap.reset()

Restores the default bindings.

```lua
uji.keymap.reset()
```

## uji.keymap.list()

Returns one row per binding, with `mode`, `key`, and one of `action`,
`command` or `unbound = true`.

```lua
for _, row in ipairs(uji.keymap.list()) do
  if row.command then
    uji.notify(row.key .. " runs /" .. row.command)
  end
end
```

## Default bindings

| Keys | Action | Modes |
|---|---|---|
| Ctrl+C | `quit` | all |
| Ctrl+A, Ctrl+E | `cursor_start`, `cursor_end` | normal, suggest, prompt, select |
| Ctrl+B, Ctrl+F | `cursor_left`, `cursor_right` | normal, suggest, prompt, select |
| Alt+B, Alt+F | `word_left`, `word_right` | normal, suggest, prompt, select |
| Ctrl+H | `backspace` | normal, suggest, prompt, select |
| Ctrl+D | `delete_forward` | normal, suggest, prompt, select |
| Ctrl+W, Alt+Backspace | `delete_word_back` | normal, suggest, prompt, select |
| Alt+D | `delete_word_forward` | normal, suggest, prompt, select |
| Ctrl+U, Ctrl+K | `delete_to_start`, `delete_to_end` | normal, suggest, prompt, select |
| Ctrl+Y | `yank` | normal, suggest, prompt, select |
| Ctrl+T | `transpose` | normal, suggest, prompt, select |
| Ctrl+P, Ctrl+N | `history_prev`, `history_next` | normal |
| Ctrl+P, Ctrl+N | `modal_up`, `modal_down` | select, suggest, confirm |
| Ctrl+G | `modal_cancel` | select, suggest, confirm |
| Shift+Enter, Alt+Enter, Ctrl+J | `insert_newline` | normal |
| Ctrl+V | `paste_image` | normal |

Enter, Esc, Tab, the arrow keys, and `y` and `n` in the approval question work
without a binding. A binding on one of these keys overrides it.

## Actions

`nothing`, `quit`, `interrupt`, `toggle_thinking`, `submit`, `clear_input`,
`backspace`, `delete_forward`, `delete_word_back`, `delete_word_forward`,
`delete_to_start`, `delete_to_end`, `yank`, `paste_image`, `transpose`, `insert_newline`,
`cursor_left`, `cursor_right`, `cursor_start`, `cursor_end`, `word_left`,
`word_right`, `scroll_up`, `scroll_down`, `page_up`, `page_down`,
`scroll_top`, `scroll_bottom`, `history_prev`, `history_next`, `modal_up`,
`modal_down`, `modal_accept`, `modal_cancel`, `suggest_complete`,
`confirm_allow`, `confirm_deny`, `confirm_toggle`.

[`uji.action.add`](action.md) adds your own.
