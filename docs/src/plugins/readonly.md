# readonly

Refuses edits in the directories you list, so the model can read them but not
change them.

```lua
require("readonly").setup({ "~/reference/other-project" })
```

It also takes one table, `setup({ paths = { ... } })`.
