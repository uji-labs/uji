# Available APIs

Every function lives under the global `uji` table. A function that finishes later takes a callback as its last argument, which receives the result, or `nil` and an error message. Called without the callback from a slash command, a key binding or a timer, it waits and returns the result instead. A function that starts background work returns a function that stops it. Wrong arguments raise an error at the call.

## Tools

| Function | Does |
|---|---|
| [`uji.tool.add(name, spec)`](tool.md#ujitooladdname-spec) | Registers a tool the model can call, or replaces the tool with the same name. |
| [`uji.tool.remove(name)`](tool.md#ujitoolremovename) | Removes a tool and returns `true` if it existed. |
| [`uji.tool.list()`](tool.md#ujitoollist) | Returns the names of every registered tool. |
| [`uji.tool.disable(names)`](tool.md#ujitooldisablenames) | Turns tools off. The model still sees them, and uji denies any call to them. |
| [`uji.tool.enable(names)`](tool.md#ujitoolenablenames) | Turns tools back on after `uji.tool.disable`. |
| [`uji.tool.policy(rules)`](tool.md#ujitoolpolicyrules) | Sets which tool calls run without asking, which ask first, and which uji refuses. |
| [`uji.tool.confine(enabled)`](tool.md#ujitoolconfineenabled) | With `true`, limits `read_file`, `edit_file` and `write_file` to the working directory and the roots from `uji.tool.roots`. |
| [`uji.tool.roots(paths)`](tool.md#ujitoolrootspaths) | Replaces the directories the file tools may reach besides the working directory, and returns the list. |

## Slash commands

| Function | Does |
|---|---|
| [`uji.command.add(name, spec)`](command.md#ujicommandaddname-spec) | Registers `/name`, or replaces the Lua command with the same name. |
| [`uji.command.remove(name)`](command.md#ujicommandremovename) | Removes a Lua command and returns `true` if it existed. |
| [`uji.command.list()`](command.md#ujicommandlist) | Returns the names of the Lua commands in alphabetical order. |

## Keys

| Function | Does |
|---|---|
| [`uji.keymap.add(mode, key, binding)`](keymap.md#ujikeymapaddmode-key-binding) | Binds a key in one mode, replacing what the key did there. |
| [`uji.keymap.remove(mode, key)`](keymap.md#ujikeymapremovemode-key) | Unbinds a key in one mode, including a default binding. |
| [`uji.keymap.reset()`](keymap.md#ujikeymapreset) | Restores the default bindings. |
| [`uji.keymap.list()`](keymap.md#ujikeymaplist) | Returns one row per binding, with `mode`, `key`, and one of `action`, `command` or `unbound = true`. |

## Actions

| Function | Does |
|---|---|
| [`uji.action.add(name, handler)`](action.md#ujiactionaddname-handler) | Registers an action. |
| [`uji.action.remove(name)`](action.md#ujiactionremovename) | Removes an action you added and returns `true` if it existed. |
| [`uji.action.list()`](action.md#ujiactionlist) | Returns the names of every action, built-in and added, in alphabetical order. |

## Windows, pickers and appearance

| Function | Does |
|---|---|
| [`uji.ui.open_win(opts)`](ui.md#ujiuiopen_winopts) | Opens a window and returns its id. |
| [`uji.ui.set_lines(id, lines)`](ui.md#ujiuiset_linesid-lines) | Replaces a window's content. |
| [`uji.ui.clear(id)`](ui.md#ujiuiclearid) | Empties a window. |
| [`uji.ui.set_size(id, size)`](ui.md#ujiuiset_sizeid-size) | Changes a window's size to rows or columns, `"fill"` or `"auto"`. |
| [`uji.ui.set_title(id, title)`](ui.md#ujiuiset_titleid-title) | Sets the title in a window's border, or removes it when `title` is `nil`. |
| [`uji.ui.close_win(id)`](ui.md#ujiuiclose_winid) | Closes a window and returns `true` if it was open. |
| [`uji.ui.select(opts, on_done)`](ui.md#ujiuiselectopts-on_done) | Shows a list to choose from. |
| [`uji.ui.pick(opts, on_done)`](ui.md#ujiuipickopts-on_done) | Shows a fuzzy finder with a preview pane. |
| [`uji.ui.prompt(opts, on_done)`](ui.md#ujiuipromptopts-on_done) | Asks for a line of text. |
| [`uji.ui.exec(cmd)`](ui.md#ujiuiexeccmd) | Hides uji, runs a program in the terminal, and comes back when it exits. |
| [`uji.ui.configure(opts)`](ui.md#ujiuiconfigureopts) | Sets colours and screen behaviour. |

## Status and footer

| Function | Does |
|---|---|
| [`uji.status.provider()`](status.md#ujistatusprovider) | Returns the name of the current provider, or `nil` before one is set. |
| [`uji.status.model()`](status.md#ujistatusmodel) | Returns the current model id, or `nil` before one is set. |
| [`uji.status.effort()`](status.md#ujistatuseffort) | Returns the reasoning effort, such as `"medium"`, or `nil` when reasoning is off. |
| [`uji.status.context()`](status.md#ujistatuscontext) | Returns a table with `used`, the estimated tokens in the conversation, and `window`, the model's context size when uji knows it. |
| [`uji.status.queue()`](status.md#ujistatusqueue) | Returns the messages you typed while the model worked, which uji has not sent yet. |
| [`uji.status.state()`](status.md#ujistatusstate) | Returns `"working"` while a turn runs and `"idle"` otherwise. |
| [`uji.status.elapsed()`](status.md#ujistatuselapsed) | Returns the seconds since the current turn started, or `nil` when idle. |
| [`uji.status.loader_frame()`](status.md#ujistatusloader_frame) | Returns the loader frame to draw now, from `waiting.loader.frames` in [`uji.ui.configure`](ui.md#ujiuiconfigureopts). |
| [`uji.status.add(name, render, opts)`](status.md#ujistatusaddname-render-opts) | Registers a footer segment. |
| [`uji.status.remove(name)`](status.md#ujistatusremovename) | Removes a segment and returns `true` if it existed. |
| [`uji.status.list()`](status.md#ujistatuslist) | Returns the segment names in priority order. |
| [`uji.status.render()`](status.md#ujistatusrender) | Calls every segment in priority order and returns the values that are not `nil`. |

## Model context

| Function | Does |
|---|---|
| [`uji.context.add(name, provide, opts)`](context.md#ujicontextaddname-provide-opts) | Registers a function that uji calls at the start of every turn. |
| [`uji.context.remove(name)`](context.md#ujicontextremovename) | Removes a context function and returns `true` if it existed. |
| [`uji.context.list()`](context.md#ujicontextlist) | Returns the names of the context functions, in the order uji calls them. |
| [`uji.context.configure(opts)`](context.md#ujicontextconfigureopts) | Sets how long the provider caches the conversation, and when uji compacts. |

## Events

| Function | Does |
|---|---|
| [`uji.on(event, handler, opts)`](events.md#ujionevent-handler-opts) | Adds a handler for an event and returns the handler's name. |
| [`uji.off(event, name)`](events.md#ujioffevent-name) | Removes the handler with that name and returns `true` if it existed. |
| [`uji.emit(event, payload)`](events.md#ujiemitevent-payload) | Runs the handlers of any event with the payload you give. |

## Session

| Function | Does |
|---|---|
| [`uji.session.info()`](session.md#ujisessioninfo) | Returns a table with the session's `id`, `title` and `directory`. |
| [`uji.session.messages()`](session.md#ujisessionmessages) | Returns the transcript as a list of tables with `type` and `text`. |
| [`uji.session.usage()`](session.md#ujisessionusage) | Returns the tokens spent in this session. |
| [`uji.session.set_title(title)`](session.md#ujisessionset_titletitle) | Renames the session, saves the name, and fires `session_titled`. |
| [`uji.session.submit(text)`](session.md#ujisessionsubmittext) | Sends a message as if you typed it. |
| [`uji.session.interrupt()`](session.md#ujisessioninterrupt) | Stops the current turn, or the running `!` command. |

## Input line

| Function | Does |
|---|---|
| [`uji.input.get()`](input.md#ujiinputget) | Returns the text on the input line. |
| [`uji.input.set(text)`](input.md#ujiinputsettext) | Replaces the text on the input line. |
| [`uji.input.append(text)`](input.md#ujiinputappendtext) | Adds text to the end of the input line. |
| [`uji.input.clear()`](input.md#ujiinputclear) | Empties the input line. |
| [`uji.input.capture(handler)`](input.md#ujiinputcapturehandler) | Sends every key press to `handler` instead of the normal bindings, until `uji.input.release` runs. |
| [`uji.input.release()`](input.md#ujiinputrelease) | Returns the keyboard to the normal bindings. |

## Providers

| Function | Does |
|---|---|
| [`uji.provider.add(spec)`](provider.md#ujiprovideraddspec) | Adds a provider, or merges `spec` into the provider with the same `id`. |
| [`uji.provider.remove(id)`](provider.md#ujiproviderremoveid) | Removes a provider and returns `true` if it existed. |
| [`uji.provider.list()`](provider.md#ujiproviderlist) | Returns one table per provider with `id`, `name`, `wire`, `base_url` and `models`. |

## Request formats

| Function | Does |
|---|---|
| [`uji.wire.add(name, spec)`](wire.md#ujiwireaddname-spec) | Registers a wire, or replaces the wire with the same name. |
| [`uji.wire.remove(name)`](wire.md#ujiwireremovename) | Removes a wire and returns `true` if it existed. |
| [`uji.wire.list()`](wire.md#ujiwirelist) | Returns the names of the registered wires. |

## Processes

| Function | Does |
|---|---|
| [`uji.job.start(opts)`](job.md#ujijobstartopts) | Starts a process and returns a job table. |

## HTTP

| Function | Does |
|---|---|
| [`uji.http.request(opts, on_done)`](http.md#ujihttprequestopts-on_done) | Sends an HTTP request and returns a function that cancels it. |

## Files

| Function | Does |
|---|---|
| [`uji.fs.read(path, on_done)`](fs.md#ujifsreadpath-on_done) | Reads a whole file. |
| [`uji.fs.lines(path, opts, on_done)`](fs.md#ujifslinespath-opts-on_done) | Reads a range of lines from a text file. |
| [`uji.fs.write(path, content, on_done)`](fs.md#ujifswritepath-content-on_done) | Writes a file, creating missing directories. |

## JSON

| Function | Does |
|---|---|
| [`uji.json.encode(value)`](json.md#ujijsonencodevalue) | Turns a Lua value into a JSON string. |
| [`uji.json.decode(text, opts)`](json.md#ujijsondecodetext-opts) | Turns a JSON string into a Lua value. |
| [`uji.json.array(table)`](json.md#ujijsonarraytable) | Marks a table as a JSON array, so it encodes as `[]` even when empty. |

## Packs

| Function | Does |
|---|---|
| [`uji.pack.add(specs)`](pack.md#ujipackaddspecs) | Installs and loads packs. |
| [`uji.pack.list()`](pack.md#ujipacklist) | Returns every directory uji searches for modules and `plugin/` files, starting with your config directory. |
| [`uji.pack.update()`](pack.md#ujipackupdate) | Pulls every installed git pack and records the new commits in the lock file. |

## Timers and notices

| Function | Does |
|---|---|
| [`uji.schedule(callback)`](timers.md#ujischedulecallback) | Runs `callback` once the code that called it has finished. |
| [`uji.defer(seconds, callback)`](timers.md#ujideferseconds-callback) | Runs `callback` after a delay and returns a function that cancels it. |
| [`uji.notify(message)`](timers.md#ujinotifymessage) | Shows a notice in the transcript. |

## Runtime

| Function | Does |
|---|---|
| [`uji.task.spawn(fn, ...)`](runtime.md#ujitaskspawnfn-) | Starts a function as a task that runs alongside the rest of uji. |
| [`uji.sleep(seconds)`](runtime.md#ujisleepseconds) | Pauses the current task. |
| [`uji.promise()`](runtime.md#ujipromise) | Returns a promise that tasks can wait on. |
| [`uji.net.request(opts)`](runtime.md#ujinetrequestopts) | Sends an HTTP request and returns the answer. |
| [`uji.net.open(opts)`](runtime.md#ujinetopenopts) | Sends an HTTP request and streams the answer. |
| [`uji.net.listen(port)`](runtime.md#ujinetlistenport) | Accepts connections on a local port. |
| [`uji.proc.spawn(argv, opts)`](runtime.md#ujiprocspawnargv-opts) | Starts a process. |
| [`uji.db.open(path)`](runtime.md#ujidbopenpath) | Opens a SQLite database. |
| [`uji.os`](runtime.md#system) | Reads the platform, the environment and the clock. |
| [`uji.keychain`](runtime.md#ujikeychaingetservice-account) | Reads and writes secrets in the system keychain. |
| [`uji.clipboard`](runtime.md#ujiclipboardget) | Reads and writes the system clipboard. |
| [`uji.regex(pattern)`](runtime.md#ujiregexpattern) | Compiles a regular expression. |
| [`uji.glob(pattern, opts)`](runtime.md#ujiglobpattern-opts) | Compiles a glob. |
| [`uji.fuzzy(query, items)`](runtime.md#ujifuzzyquery-items) | Ranks strings against a query. |
| [`uji.markdown(source)`](runtime.md#ujimarkdownsource) | Parses Markdown into events. |
| [`uji.width(text)`](runtime.md#ujiwidthtext) | Measures text in terminal columns. |
| [`uji.base64`](runtime.md#encoding) | Encodes and decodes base64. |
| [`uji.sha256(data)`](runtime.md#encoding) | Hashes data. |
| [`uji.random(count)`](runtime.md#encoding) | Returns random bytes. |
