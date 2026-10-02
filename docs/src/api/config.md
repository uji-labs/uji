# uji.config

## uji.config.files(folder, opts, on_done)

Reads the files in `folder` of your config directory and of each pack, in the
order [`uji.pack.list`](pack.md#ujipacklist) gives. `on_done` receives a list
of tables with `name`, the file name, `path`, the full path, and `text`, the
contents. Folders inside `folder` are left out. These reads are not limited to
the working directory, because the files belong to your config.

| Option | Type | Meaning |
|---|---|---|
| `project` | boolean | With `true`, also reads `.uji/<folder>` in the session's directory, or in the nearest directory above it that has one. Those files come last and have `project = true`. |

Raises an error when `folder` is empty, absolute or reaches outside with `..`.

```lua
uji.config.files("agents", { project = true }, function(files)
  for _, file in ipairs(files) do
    uji.notify((file.project and "project: " or "") .. file.name)
  end
end)
```
