# Processes

## uji.proc.spawn(argv, opts)

Starts the program named by the first item of the list `argv`, with the rest
as its arguments. The result is a process, or `nil` and an error message. If
the process is still running when nothing refers to it any more, uji kills it
and every process it started. A process given the terminal is killed alone.

A process that is not given the terminal has none: a program that asks for a
password on the terminal, such as `ssh` or `sudo`, fails at once instead of
waiting for an answer.

| Option | Type | Meaning |
|---|---|---|
| `cwd` | string | The directory to run in. |
| `env` | table | Extra environment variables. |
| `stdio` | string | `"pipe"`, the default, to read and write the process, or `"inherit"` to give it the terminal. |

| Member | Meaning |
|---|---|
| `proc.pid` | The process id. |
| `proc:line()` | The next line of output with `"stdout"` or `"stderr"`, or `nil` once both streams end. |
| `proc:lines()` | An iterator over the remaining lines and their streams. |
| `proc:write(data)` | Writes `data` to the process's input. |
| `proc:close()` | Closes the process's input. |
| `proc:kill()` | Kills the process and every process it started. A process given the terminal is killed alone. |
| `proc:wait()` | Waits for the process to exit and gives a table with `code`, `signal` and `success`. |
