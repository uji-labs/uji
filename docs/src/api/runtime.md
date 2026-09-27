# Runtime

These functions are the building blocks the rest of uji is written with. A
plugin can use them to run work in the background, talk to the network, start
processes, keep data in SQLite and read the system.

## Tasks

A task is a function that runs alongside the rest of uji. Anything that waits
on the network, a process, the keychain or a timer pauses only the task that
called it, and uji keeps running meanwhile. Your config, slash commands, key
bindings, actions, timers from `uji.schedule` and `uji.defer`, and tool
functions all run as tasks. Calling something that waits from outside a task
raises an error.

### uji.task.spawn(fn, ...)

Starts `fn` as a new task with the arguments that follow, and returns a task
object. An error inside the task shows as a notice.

### task:cancel()

Stops the task. Connections and processes that only the task was using are
closed.

### uji.sleep(seconds)

Pauses the task for `seconds`, which may be a fraction.

### uji.task.race(fn, ...)

Runs every function at once inside the current task and waits for the first to
finish. The result is its position followed by what it returned, and the others
stop there. An error in the first to finish is raised again, and cancelling the
current task stops all of them.

### uji.task.timeout(seconds, fn)

Runs `fn` inside the current task for at most `seconds`. When `fn` finishes in
time the result is `true` followed by what it returned. Otherwise `fn` stops and
the result is `false`.

### uji.promise()

Creates a promise that tasks can wait on until another task settles it.

| Member | Meaning |
|---|---|
| `promise:resolve(...)` | Settles the promise with the values given. The result is `true` the first time and `false` after. |
| `promise:await()` | Waits until the promise is settled and gives back its values. |
| `promise.settled` | `true` once the promise is settled. |

## Network

### uji.net.request(opts)

Sends an HTTP request and waits for the answer, a table with `status`,
`headers` and `body`. When no answer comes back the result is `nil` and an
error message. An error status still counts as an answer.

| Option | Type | Meaning |
|---|---|---|
| `url` | string | The address. Required. |
| `method` | string | The method. The default is `"GET"`. |
| `headers` | table | Header names and values. |
| `body` | string | The request body. |
| `timeout` | number | Seconds to wait for the whole answer. |

### uji.net.open(opts)

Sends a request like `uji.net.request`, but hands back a response object as
soon as the headers arrive, so the body can be read while it streams. It takes
the same options plus `idle`, the seconds without data after which reading
fails, 120 by default. A failed request gives `nil` and an error message.

| Member | Meaning |
|---|---|
| `response.status` | The status code. |
| `response.headers` | Header names and values. |
| `response:line(seconds)` | The next line, `nil` at the end of the body, or `false` if `seconds` pass first. Without `seconds` it waits as long as the line takes. |
| `response:lines()` | An iterator over the remaining lines, for a `for` loop. |
| `response:read()` | Everything left in the body, once it has arrived. |

### uji.net.listen(port)

Listens on `port` on the local machine, or on a free port when `port` is `0`.
The result is a server, or `nil` and an error message.

| Member | Meaning |
|---|---|
| `server.port` | The port it listens on. |
| `server:accept()` | The next connection, or `nil` and an error message once the server is closed. |
| `server:close()` | Stops listening. |
| `conn:line(seconds)` | The next line, `nil` when the other side closes, or `false` if `seconds` pass first. Without `seconds` it waits as long as the line takes. |
| `conn:read(count)` | Exactly `count` bytes. |
| `conn:write(data)` | Sends `data`. |
| `conn:close()` | Closes the connection. |

## Processes

### uji.proc.spawn(argv, opts)

Starts the program named by the first item of the list `argv`, with the rest
as its arguments. The result is a process, or `nil` and an error message. The
process is killed when nothing refers to it any more.

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
| `proc:kill()` | Kills the process. |
| `proc:wait()` | Waits for the process to exit and gives a table with `code`, `signal` and `success`. |

## Storage

### uji.db.open(path)

Opens or creates the SQLite database at `path`. The result is a database, or
`nil` and an error message. Parameters are a list that fills the `?` marks in
the statement, and `uji.db.null` stands for `NULL` in that list.

| Member | Meaning |
|---|---|
| `db:exec(sql, params)` | Runs a statement and gives the number of rows it changed. Without `params`, `sql` may hold several statements. |
| `db:query(sql, params)` | The rows, as a list of tables keyed by column name. |
| `db:transaction(fn)` | Runs `fn` in a transaction and gives back what it returns. An error inside `fn` rolls the transaction back and raises again. |
| `db:close()` | Closes the database. |

## System

| Function | Gives |
|---|---|
| `uji.os.platform` | `"macos"`, `"linux"`, `"windows"` or `"other"`. |
| `uji.os.env(name)` | The value of an environment variable, or `nil` when it is unset or empty. |
| `uji.os.cwd()` | The directory uji started in. |
| `uji.os.home()` | Your home directory, or `nil`. |
| `uji.os.now()` | The time in milliseconds since the Unix epoch. |
| `uji.os.clock()` | Seconds since uji started, for measuring how long something took. |
| `uji.os.roots` | The directories whose `lua/` folder is searched before the built-in modules. |
| `uji.os.carry` | The text handed over by the last `uji.os.restart`, or `nil`. |

### uji.os.restart(opts)

Starts uji's Lua side again once the current code yields, keeping the screen.
Every task, connection and process from this run stops. `opts.args` is the
command line for the new run, `opts.roots` sets `uji.os.roots` for it, and
`opts.carry` is text it can read from `uji.os.carry`.

### uji.keychain.get(service, account)

Looks up the secret saved in the system keychain for `service` and `account`,
and gives `nil` when there is none.

### uji.keychain.set(service, account, secret)

Saves `secret` in the system keychain, then gives `true`, or `nil` and an
error message.

### uji.keychain.delete(service, account)

Removes the secret, with the same result as `uji.keychain.set`.

### uji.clipboard.get()

Reads the text on the system clipboard, or gives `nil` and an error message.

### uji.clipboard.set(text)

Puts `text` on the system clipboard and gives `true`, or `nil` and an error
message.

## Text

### uji.regex(pattern)

Compiles a regular expression into a matcher, or gives `nil` and an error
message.

### uji.glob(pattern, opts)

Compiles a glob such as `*.rs` into a matcher, or gives `nil` and an error
message. With `opts.separator = true`, `*` does not match `/`.

| Member | Meaning |
|---|---|
| `matcher:test(text)` | `true` when the pattern matches somewhere in `text`. |
| `matcher:find(text)` | The start and end positions of the first match, or `nil`. |

### uji.fuzzy(query, items)

Ranks the list of strings `items` against `query` the way the pickers do, as
positions in `items` with the best match first. An empty query gives every
position in order.

### uji.markdown(source)

Parses Markdown into a list of events. Each event is itself a list that starts
with its kind, one of `"start"`, `"end"`, `"text"`, `"code"`, `"html"`,
`"break"`, `"rule"` and `"task"`. The details of that event come next, then its
start and end byte positions in `source`.

### uji.width(text)

Counts the terminal columns `text` takes.

### uji.lossy(data)

Turns `data` into valid UTF-8, replacing each invalid byte sequence with
U+FFFD.

## Encoding

| Function | Gives |
|---|---|
| `uji.base64.encode(data, opts)` | `data` in base64. `opts.url = true` uses the URL alphabet and `opts.pad = false` leaves out padding. |
| `uji.base64.decode(text, opts)` | The decoded bytes. It takes the same options and raises an error for text that is not base64. |
| `uji.sha256(data)` | The SHA-256 digest of `data`, as 32 raw bytes. |
| `uji.random(count)` | `count` random bytes. |
