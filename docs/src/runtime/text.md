# Text

## uji.regex(pattern)

Compiles a regular expression into a matcher, or gives `nil` and an error
message.

## uji.glob(pattern, opts)

Compiles a glob such as `*.rs` into a matcher, or gives `nil` and an error
message. With `opts.separator = true`, `*` does not match `/`.

| Member | Meaning |
|---|---|
| `matcher:test(text)` | `true` when the pattern matches somewhere in `text`. |
| `matcher:find(text)` | The start and end positions of the first match, or `nil`. |

## uji.fuzzy(query, items)

Ranks the list of strings `items` against `query` the way the pickers do, as
positions in `items` with the best match first. An empty query gives every
position in order.

## uji.highlight(language, text)

Highlights `text` away from the screen's thread and gives the tokens of each
line, or `nil` when uji does not know `language`. `language` is a name such as
`"python"`, a file extension such as `"rs"`, or a file name such as
`"Makefile"`. Each token has `text` and `kind`, which is one of `"plain"`,
`"keyword"`, `"string"`, `"number"`, `"comment"`, `"func"`, `"type"` and
`"constant"`. Call it from a task, since it waits for the result.

```lua
uji.task.spawn(function()
  local lines = uji.highlight("lua", "local n = 42 -- answer")
  local kinds = {}
  for _, token in ipairs(lines[1]) do
    kinds[#kinds + 1] = token.kind .. ": " .. token.text
  end
  uji.notify(table.concat(kinds, ", "))
end)
```

## uji.markdown(source)

Parses Markdown into a list of events. Each event is itself a list that starts
with its kind, one of `"start"`, `"end"`, `"text"`, `"code"`, `"html"`,
`"math"`, `"break"`, `"rule"` and `"task"`. The details of that event come next,
then its start and end byte positions in `source`.

Math between `$` and `$`, or `\(` and `\)`, gives a `"math"` event with its TeX
source and `false`. Math between `$$` and `$$`, or `\[` and `\]`, gives one with
`true`.

## uji.width(text)

Counts the terminal columns `text` takes.

## uji.lossy(data)

Turns `data` into valid UTF-8, replacing each invalid byte sequence with
U+FFFD.
