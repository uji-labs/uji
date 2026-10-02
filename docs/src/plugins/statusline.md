# statusline

Status lines built from segments. By default it draws one line below the input
with the directory, model, reasoning effort, context use, tokens, cache hit
rate and turns.

```lua
require("statusline").setup({})
```

| Option | Meaning | Default |
|---|---|---|
| `lines` | The lines to draw. See below. | one line below the input with every segment |
| `logo` | `true` shows the uji logo while the session is empty. A table `{ lines = { ... }, color = "#f9e2af" }` shows your own. | `false` |
| `defaults` | `false` registers none of the built-in segments. | `true` |
| `separator` | Text between segments. | `"  ·  "` |

## Segments

A segment is a function registered with
[`uji.status.add`](../api/status.md#ujistatusaddname-render-opts). The built-in
ones are `cwd`, `model`, `effort`, `context`, `tokens`, `cache` and `turns`.
Adding a segment with one of these names after `setup` replaces it.

## Lines

Each line has these fields.

| Field | Meaning |
|---|---|
| `at` | `"top"` above the conversation, `"above"` just above the input, or `"below"` under it. The default is `"below"`. Lines at the same place stack in the order you list them. |
| `left`, `center`, `right` | The names of the segments on each side. `"*"` stands for every segment that no line names, so segments from other plugins still show. |
| `priority` | The layout priority of the line's window, when the place's default is not what you want. |

This setup puts the model and effort above the input, the directory and
context use below it, and the logo on an empty session.

```lua
require("statusline").setup({
  logo = true,
  lines = {
    { at = "above", left = { "model" }, right = { "effort" } },
    { at = "below", left = { "cwd", "*" }, right = { "context" } },
  },
})

uji.status.add("model", function()
  local provider = uji.status.provider()
  return provider and { text = uji.status.model() .. " · " .. provider, bold = true }
end)

uji.status.add("effort", function()
  local effort = uji.status.effort()
  return effort and { text = "effort " .. effort, color = "yellow", bold = true }
end)
```
