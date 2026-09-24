# uji.context

`uji.context` controls what the model sees besides the conversation. It adds
text to each turn, and it sets when uji compacts old messages.

### uji.context.add(name, provide, opts)

Registers a function that uji calls at the start of every turn. What it
returns decides where the text goes.

| Return | Effect |
|---|---|
| a string | uji appends it to the system prompt. |
| `{ text = "...", at = "turn" }` | uji adds the text after your message and keeps it in the conversation. The transcript does not show it. |
| `nil` | uji adds nothing this turn. |

Text added with `at = "turn"` stays in the conversation. When it stops being
true, return a line that says so once, such as `Plan mode is off.` Return text
that changes between turns this way, not as a string. When the system prompt
changes, the provider cannot reuse its cache for the conversation.

`opts.priority` orders the functions, lowest first. The default is 50. A
function with the same name replaces the earlier one.

```lua
uji.context.add("branch", function()
  local branch = io.popen("git branch --show-current"):read("*l")
  if branch and branch ~= "" then
    return "The current git branch is " .. branch .. "."
  end
end, { priority = 20 })
```

### uji.context.remove(name)

Removes a context function and returns `true` if it existed.

```lua
uji.context.remove("branch")
```

### uji.context.list()

Returns the names of the context functions, in the order uji calls them.

```lua
local names = uji.context.list()
```

### uji.context.configure(opts)

Sets how long the provider caches the conversation, and when uji compacts.
When the conversation grows past the model's context window minus a reserve,
uji summarises older messages before the next turn.

| Key | Meaning | Default |
|---|---|---|
| `cache` | How long the provider keeps the conversation cached between turns. `"off"`, `"short"` for 5 minutes, or `"long"` for 1 hour. A cache write costs more with `"long"`, and the cache survives longer pauses. It applies to models with `cache = true` in [`uji.provider.add`](provider.md). | `"short"` |
| `compaction.enabled` | Compact automatically. `/compact` works either way. | `true` |
| `compaction.reserve` | Tokens to keep free for the reply. | the model's output limit, or 20,000 when unknown, at most a quarter of the window |
| `compaction.keep_recent` | Tokens of recent messages to keep word for word. | `20000` |

Raises an error for an unknown key or an unknown `cache` value.

```lua
uji.context.configure({
  cache = "long",
  compaction = { keep_recent = 40000 },
})
```
