# uji.fs

Reading, writing, listing and globbing go through the same checks as the file
tools, and their relative paths start at the working directory.

## uji.fs.read(path, on_done)

Reads a whole file. `on_done` receives the contents, or `nil` and an error
message.

```lua
uji.fs.read("Cargo.toml", function(text, err)
  if text then
    uji.notify(#text .. " bytes")
  end
end)
```

## uji.fs.lines(path, opts, on_done)

Reads a range of lines from a text file. It refuses directories and binary
files.

| Option | Type | Meaning |
|---|---|---|
| `offset` | integer | The first line to return, counting from 1. The default is 1. |
| `limit` | integer | The most lines to return. The default is all of them. |
| `max_line` | integer | Cuts lines longer than this many bytes. |

`on_done` receives a table with `lines`, the list of lines, `cut`, whose keys
are the positions of lines that `max_line` cut, and `total`, the number of
lines in the file.

```lua
uji.fs.lines("README.md", { offset = 1, limit = 20 }, function(page, err)
  if page then
    uji.notify(string.format("showing %d of %d lines", #page.lines, page.total))
  end
end)
```

## uji.fs.write(path, content, on_done)

Writes a file, creating missing directories. `on_done` receives a table whose
`created` field is `true` when the file did not exist, or `nil` and an error
message.

```lua
uji.fs.write("notes/todo.md", "- write the docs\n", function(result, err)
  if result and result.created then
    uji.notify("created notes/todo.md")
  end
end)
```

## uji.fs.list(path, on_done)

Lists a directory. `on_done` receives a list of tables with `name` and
`type`, which is `"file"`, `"dir"`, `"link"` or `"other"`, sorted by name, or
`nil` and an error message.

```lua
uji.fs.list("src", function(entries, err)
  if entries then
    uji.notify(#entries .. " entries in src")
  end
end)
```

## uji.fs.glob(pattern, on_done)

Lists the paths that match `pattern`, in alphabetical order. `*` stands for any
part of a name, `?` for one character, `[abc]` for one of the characters
between the brackets, and `**` for any number of directories. A relative
pattern gives paths relative to the working directory for matches inside it.
`on_done` receives the list, or `nil` and an error message when the pattern is
not valid.

```lua
uji.fs.glob("src/**/*.rs", function(found, err)
  if found then
    uji.notify(#found .. " Rust files")
  end
end)
```

## uji.fs.join(base, ...)

Joins `base` and the parts after it into one path, with the separator the
system uses.

```lua
local projects = uji.fs.join("~", ".claude", "projects")
```
