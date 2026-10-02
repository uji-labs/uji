# The system prompt

Your config can change the instructions that the model gets with every message
you send.

## Adding project notes

Adds `NOTES.md` from the working directory to the system prompt on every
turn.

```lua
uji.context.add("notes", function()
  local file = io.open(uji.session.info().directory .. "/NOTES.md")
  if not file then
    return nil
  end
  local notes = file:read("a")
  file:close()
  return "Project notes from NOTES.md:\n\n" .. notes
end)
```

## A reminder at the end of the turn

Text returned with `at = "turn"` goes after the conversation instead of into
the system prompt.

```lua
uji.context.add("reminder", function()
  return { text = "Run the tests before you say you are done.", at = "turn" }
end)
```

## Rewriting the whole prompt

A `before_turn` hook returns a new system prompt.

```lua
uji.on("before_turn", function(turn)
  return turn.system .. "\n\nWrite commit messages in the imperative mood."
end)
```

To replace the prompt entirely, override the built-in `uji.core.prompt`
module, as [Rebuilding uji](../rebuilding/index.md) shows.
