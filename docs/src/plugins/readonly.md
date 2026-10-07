# readonly

Refuses edits in the directories you list, so the model can read them but not
change them.

```lua
uji.tool.roots({ "~/reference/other-project" })
require("readonly").setup({ "~/reference/other-project" })
```

It also takes one table, `setup({ paths = { ... }, priority = 20 })`.
`priority` is the priority of its `before_tool` hook, `20` by default.
