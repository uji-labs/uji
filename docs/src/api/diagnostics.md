# uji.diagnostics

When drawing the screen goes wrong, uji keeps going and records what happened
in `diagnostics.log` in the [data directory](../configuration/files.md), instead
of showing it in the transcript. That covers:

- a frame that fails to draw;
- a screen, view replacement or toolbar item that raises an error;
- a list or box that fails to open.

Each entry has the time, where the error came from, the error, and the stack
of calls when uji has one. An error that repeats is recorded once. Once the
file passes one megabyte, uji keeps only the newest half megabyte of it.
`/diagnostics` lists the entries, newest first, with the whole entry in the
preview.

## uji.diagnostics.list(on_done)

Returns the recorded entries, newest first. Each is a table with `time`, such
as `"2026-10-07 02:51:34"`, `source`, which is one of `render`, `screen`,
`modal` and `view`, and `text`, the error followed by its stack of calls.
`on_done` receives the list. Without it, the call waits and returns the list.

```lua
for _, entry in ipairs(uji.diagnostics.list()) do
  uji.notify(entry.time .. " " .. entry.source)
end
```
