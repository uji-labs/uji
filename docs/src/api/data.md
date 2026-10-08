# uji.data

Files a plugin keeps in the [data directory](../configuration/files.md),
readable only by you.

## uji.data.read(name, on_done)

Reads the file `name`. `on_done` receives its text, or `nil` and an error
message. Raises an error when `name` is not a plain file name.

```lua
uji.data.read("bookmarks.json", function(text)
  local saved = text and uji.json.decode(text) or {}
  uji.notify(#saved .. " bookmarks")
end)
```

## uji.data.write(name, text, on_done)

Writes `text` to the file `name`, replacing what was there. `on_done` receives
`true`, or `nil` and an error message. Raises an error when `name` is not a
plain file name or `text` is not a string.

```lua
uji.data.write("bookmarks.json", uji.json.encode({ "notes.md" }))
```
