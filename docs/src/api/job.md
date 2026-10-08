# uji.job

`uji.job` runs a process in the background and streams its output to Lua.

## uji.job.start(opts)

Starts a process and returns a job table.

| Option | Type | Meaning |
|---|---|---|
| `cmd` | string or list | Required. A string is a shell command. A list is the program and its arguments. |
| `cwd` | string | The directory to run in. The default is uji's working directory. |
| `timeout` | number | Seconds before uji kills the process. |
| `on_stdout` | function | Receives each line the process writes to standard output. |
| `on_stderr` | function | Receives each line the process writes to standard error. |
| `on_exit` | function | Receives the exit code. When uji stopped the process, it receives `-1` and `"timeout"` or `"stopped"`. |

The job table has three functions:
- `job.send(text)` writes a line to the process's standard input, adding a
  newline if `text` lacks one.
- `job.close()` closes standard input.
- `job.stop()` kills the process and every process it started.

Raises an error when `cmd` is missing or empty.

```lua
local job = uji.job.start({
  cmd = { "git", "status", "--short" },
  on_stdout = function(line)
    uji.notify(line)
  end,
  on_exit = function(code)
    if code ~= 0 then
      uji.notify("git status failed with " .. code)
    end
  end,
})
job.close()
```
