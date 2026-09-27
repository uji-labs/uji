# Runtime

These functions are the building blocks the rest of uji is written with. A
plugin can use them to run work in the background, talk to the network, start
processes, keep data in SQLite and read the system.

## Tasks

A task is a function that runs alongside the rest of uji. A function marked
*waits* pauses the task that calls it until its result is ready, and uji keeps
running in the meantime. Your config, slash commands, key bindings, actions,
timers from `uji.schedule` and `uji.defer`, and tool functions all run as
tasks. Calling a waiting function outside a task raises an error.

### uji.task.spawn(fn, ...)

Starts `fn` as a new task with the arguments that follow, and returns a task
object. An error inside the task shows as a notice.

### task:cancel()

Stops the task. Connections and processes that only the task was using are
closed.

### uji.sleep(seconds)

Waits. Pauses the task for `seconds`, which may be a fraction.

### uji.promise()

Returns a promise that tasks can wait on until another task settles it.

| Member | Meaning |
|---|---|
| `promise:resolve(...)` | Settles the promise with the values given. Returns `true` the first time and `false` after. |
| `promise:await()` | Waits. Returns the values the promise was settled with. |
| `promise.settled` | `true` once the promise is settled. |

## Network

### uji.net.request(opts)

Waits. Sends an HTTP request and returns a table with `status`, `headers` and
`body`, or `nil` and an error message when no answer came back. An answer with
an error status is still returned as a table.

| Option | Type | Meaning |
|---|---|---|
| `url` | string | The address. Required. |
| `method` | string | The method. The default is `"GET"`. |
| `headers` | table | Header names and values. |
| `body` | string | The request body. |
| `timeout` | number | Seconds to wait for the whole answer. |

### uji.net.open(opts)

Waits. Sends a request like `uji.net.request` and returns as soon as the
headers arrive, so the body can be read as it streams. Returns a response
object, or `nil` and an error message. It takes the same options, plus `idle`,
the seconds without data after which reading fails. The default is 120.

| Member | Meaning |
|---|---|
| `response.status` | The status code. |
| `response.headers` | Header names and values. |
| `response:line(seconds)` | Waits. Returns the next line, `nil` at the end of the body, or `false` when `seconds` pass first. Without `seconds` it waits as long as the line takes. |
| `response:lines()` | An iterator over the remaining lines, for a `for` loop. |
| `response:read()` | Waits. Returns the rest of the body. |

### uji.net.listen(port)

Listens for connections on `port` on the local machine, or on a free port when
`port` is `0`. Returns a server, or `nil` and an error message.

| Member | Meaning |
|---|---|
| `server.port` | The port it listens on. |
| `server:accept()` | Waits. Returns the next connection, or `nil` and an error message once the server is closed. |
| `server:close()` | Stops listening. |
| `conn:line()` | Waits. Returns the next line, or `nil` when the other side closes. |
| `conn:read(count)` | Waits. Returns exactly `count` bytes. |
| `conn:write(data)` | Waits. Sends `data`. |
| `conn:close()` | Waits. Closes the connection. |

## Processes

### uji.proc.spawn(argv, opts)

Starts the program named by the first item of the list `argv`, with the rest
as its arguments. Returns a process, or `nil` and an error message. The process
is killed when nothing refers to it any more.

| Option | Type | Meaning |
|---|---|---|
| `cwd` | string | The directory to run in. |
| `env` | table | Extra environment variables. |
| `stdio` | string | `"pipe"`, the default, to read and write the process, or `"inherit"` to give it the terminal. |

| Member | Meaning |
|---|---|
| `proc.pid` | The process id. |
| `proc:line()` | Waits. Returns the next line of output and `"stdout"` or `"stderr"`, or `nil` when both streams end. |
| `proc:lines()` | An iterator over the remaining lines and their streams. |
| `proc:write(data)` | Waits. Writes `data` to the process's input. |
| `proc:close()` | Waits. Closes the process's input. |
| `proc:kill()` | Kills the process. |
| `proc:wait()` | Waits. Returns a table with `code`, `signal` and `success` once the process exits. |

## Storage

### uji.db.open(path)

Opens or creates the SQLite database at `path`. Returns a database, or `nil`
and an error message. Parameters are a list that fills the `?` marks in the
statement, and `uji.db.null` stands for `NULL` in that list.

| Member | Meaning |
|---|---|
| `db:exec(sql, params)` | Runs a statement and returns the number of rows it changed. Without `params`, `sql` may hold several statements. |
| `db:query(sql, params)` | Returns the rows as a list of tables keyed by column name. |
| `db:transaction(fn)` | Runs `fn` in a transaction and returns what it returns. An error inside `fn` rolls the transaction back and raises again. |
| `db:close()` | Closes the database. |

## System

| Function | Returns |
|---|---|
| `uji.os.platform` | `"macos"`, `"linux"`, `"windows"` or `"other"`. |
| `uji.os.env(name)` | The value of an environment variable, or `nil` when it is unset or empty. |
| `uji.os.cwd()` | The directory uji started in. |
| `uji.os.home()` | Your home directory, or `nil`. |
| `uji.os.now()` | The time in milliseconds since the Unix epoch. |
| `uji.os.clock()` | Seconds since uji started, for measuring how long something took. |

### uji.keychain.get(service, account)

Waits. Returns the secret saved in the system keychain for `service` and
`account`, or `nil` when there is none.

### uji.keychain.set(service, account, secret)

Waits. Saves `secret` in the system keychain. Returns `true`, or `nil` and an
error message.

### uji.keychain.delete(service, account)

Waits. Removes the secret. Returns `true`, or `nil` and an error message.

### uji.clipboard.get()

Returns the text on the system clipboard, or `nil` and an error message.

### uji.clipboard.set(text)

Puts `text` on the system clipboard. Returns `true`, or `nil` and an error
message.

## Text

### uji.regex(pattern)

Compiles a regular expression and returns a matcher, or `nil` and an error
message.

### uji.glob(pattern, opts)

Compiles a glob such as `*.rs` and returns a matcher, or `nil` and an error
message. With `opts.separator = true`, `*` does not match `/`.

| Member | Meaning |
|---|---|
| `matcher:test(text)` | `true` when the pattern matches somewhere in `text`. |
| `matcher:find(text)` | The start and end positions of the first match, or `nil`. |

### uji.fuzzy(query, items)

Ranks the list of strings `items` against `query` the way the pickers do, and
returns the positions of the matches, best first. An empty query returns every
position in order.

### uji.markdown(source)

Parses Markdown and returns its events as a list. Each event is a list whose
first item is `"start"`, `"end"`, `"text"`, `"code"`, `"html"`, `"break"`,
`"rule"` or `"task"`, followed by the details of that event and the start and
end byte positions in `source`.

### uji.width(text)

Returns how many terminal columns `text` takes.

## Encoding

| Function | Returns |
|---|---|
| `uji.base64.encode(data, opts)` | `data` in base64. `opts.url = true` uses the URL alphabet and `opts.pad = false` leaves out padding. |
| `uji.base64.decode(text, opts)` | The decoded bytes. It takes the same options and raises an error for text that is not base64. |
| `uji.sha256(data)` | The SHA-256 digest of `data`, as 32 raw bytes. |
| `uji.random(count)` | `count` random bytes. |
