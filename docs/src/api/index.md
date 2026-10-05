# Available APIs

Every function lives under the global `uji` table. A function that finishes later takes a callback as its last argument, which receives the result, or `nil` and an error message. Called without the callback from a slash command, a key binding or a timer, it waits and returns the result instead. A function that starts background work returns a function that stops it. Wrong arguments raise an error at the call.

## Tools

| Name | Does |
|---|---|
| [`uji.tool.add(name, spec)`](tool.md#ujitooladdname-spec) | Registers a tool the model can call, or replaces the tool with the same name. |
| [`uji.tool.remove(name)`](tool.md#ujitoolremovename) | Removes a tool and returns `true` if it existed. |
| [`uji.tool.list()`](tool.md#ujitoollist) | Returns the names of every registered tool. |
| [`uji.tool.disable(names)`](tool.md#ujitooldisablenames) | Turns tools off. The model still sees them, and uji denies any call to them. |
| [`uji.tool.enable(names)`](tool.md#ujitoolenablenames) | Turns tools back on after `uji.tool.disable`. |
| [`uji.tool.policy(rules)`](tool.md#ujitoolpolicyrules) | Sets which tool calls run without asking, which ask first, and which uji refuses. |
| [`uji.tool.confine(enabled)`](tool.md#ujitoolconfineenabled) | With `true`, limits `read_file`, `edit_file` and `write_file` to the working directory and the roots from `uji.tool.roots`. |
| [`uji.tool.roots(paths)`](tool.md#ujitoolrootspaths) | Replaces the directories the file tools may reach besides the working directory, and returns the list. |

## Commands

| Name | Does |
|---|---|
| [`uji.command.add(name, spec)`](command.md#ujicommandaddname-spec) | Registers `/name`, or replaces the command with the same name, built-in or not. |
| [`uji.command.remove(name)`](command.md#ujicommandremovename) | Removes a command and returns `true` if it existed. |
| [`uji.command.list()`](command.md#ujicommandlist) | Returns the names of every command in alphabetical order. |

## Keys

| Name | Does |
|---|---|
| [`uji.keymap.add(mode, key, binding)`](keymap.md#ujikeymapaddmode-key-binding) | Binds a key in one mode, replacing what the key did there. |
| [`uji.keymap.remove(mode, key)`](keymap.md#ujikeymapremovemode-key) | Unbinds a key in one mode, including a default binding. |
| [`uji.keymap.reset()`](keymap.md#ujikeymapreset) | Restores the default bindings. |
| [`uji.keymap.list()`](keymap.md#ujikeymaplist) | Returns one row per binding, with `mode`, `key`, and one of `action`, `command` or `unbound = true`. |

## Actions

| Name | Does |
|---|---|
| [`uji.action.add(name, handler)`](action.md#ujiactionaddname-handler) | Registers an action. |
| [`uji.action.remove(name)`](action.md#ujiactionremovename) | Removes an action you added and returns `true` if it existed. |
| [`uji.action.list()`](action.md#ujiactionlist) | Returns the names of every action, built-in and added, in alphabetical order. |

## Windows, pickers and appearance

| Name | Does |
|---|---|
| [`uji.ui.toolbar(items)`](ui.md#ujiuitoolbaritems) | Declares toolbar items on the screen and returns a handle that removes them. |
| [`uji.ui.size()`](ui.md#ujiuisize) | Returns the width and height of the terminal. |
| [`uji.ui.select(opts, on_done)`](ui.md#ujiuiselectopts-on_done) | Shows a list to choose from. |
| [`uji.ui.pick(opts, on_done)`](ui.md#ujiuipickopts-on_done) | Shows a fuzzy finder with a preview pane. |
| [`uji.ui.prompt(opts, on_done)`](ui.md#ujiuipromptopts-on_done) | Asks for a line of text. |
| [`uji.ui.confirm(opts, on_done)`](ui.md#ujiuiconfirmopts-on_done) | Asks a yes or no question, including uji's approval questions. |
| [`uji.ui.overlay(content, opts)`](ui.md#ujiuioverlaycontent-opts) | Shows a view in a box over the screen until you close it. |
| [`uji.ui.template(name, default)`](ui.md#ujiuitemplatename-default) | Returns a view that a theme can replace. |
| [`uji.ui.Markdown(text)`](ui.md#ujiuimarkdowntext) | A view that draws markdown. |
| [`uji.ui.toggle_thinking()`](ui.md#ujiuitoggle_thinking) | Shows or hides the model's reasoning in the transcript. |
| [`uji.ui.exec(cmd)`](ui.md#ujiuiexeccmd) | Hides uji, runs a program in the terminal, and comes back when it exits. |
| [`uji.ui.configure(opts)`](ui.md#ujiuiconfigureopts) | Sets colours and screen behaviour. |

## Model context

| Name | Does |
|---|---|
| [`uji.context.add(name, provide, opts)`](context.md#ujicontextaddname-provide-opts) | Registers a function that uji calls at the start of every turn. |
| [`uji.context.remove(name)`](context.md#ujicontextremovename) | Removes a context function and returns `true` if it existed. |
| [`uji.context.list()`](context.md#ujicontextlist) | Returns the names of the context functions, in the order uji calls them. |
| [`uji.context.configure(opts)`](context.md#ujicontextconfigureopts) | Sets how long the provider caches the conversation, and when uji compacts. |

## Events

| Name | Does |
|---|---|
| [`uji.on(event, handler, opts)`](events.md#ujionevent-handler-opts) | Adds a handler for an event and returns the handler's name. |
| [`uji.off(event, name)`](events.md#ujioffevent-name) | Removes the handler with that name and returns `true` if it existed. |
| [`uji.emit(event, payload)`](events.md#ujiemitevent-payload) | Runs the handlers of any event with the payload you give. |

## Session

| Name | Does |
|---|---|
| [`uji.session.info()`](session.md#ujisessioninfo) | Returns a table with the session's `id`, `title` and `directory`. |
| [`uji.session.messages()`](session.md#ujisessionmessages) | Returns the transcript as a list of tables with `type` and `text`. |
| [`uji.session.usage()`](session.md#ujisessionusage) | Returns the tokens spent in this session. |
| [`uji.session.context()`](session.md#ujisessioncontext) | Returns a table with `used`, the estimated tokens in the conversation, and `window`, the model's context size when uji knows it. |
| [`uji.session.queue()`](session.md#ujisessionqueue) | Returns the messages you typed while the model worked, which uji has not sent yet. |
| [`uji.session.state()`](session.md#ujisessionstate) | Returns `"working"` while a turn runs and `"idle"` otherwise. |
| [`uji.session.elapsed()`](session.md#ujisessionelapsed) | Returns the seconds since the current turn started, or `nil` when idle. |
| [`uji.session.set_title(title)`](session.md#ujisessionset_titletitle) | Renames the session, saves the name, and fires `session_titled`. |
| [`uji.session.submit(text)`](session.md#ujisessionsubmittext) | Sends a message as if you typed it. |
| [`uji.session.interrupt()`](session.md#ujisessioninterrupt) | Stops the current turn, or the running `!` command. |
| [`uji.session.compact()`](session.md#ujisessioncompact) | Summarises earlier messages to free context. |

## Input line

| Name | Does |
|---|---|
| [`uji.input.get()`](input.md#ujiinputget) | Returns the text on the input line. |
| [`uji.input.set(text)`](input.md#ujiinputsettext) | Replaces the text on the input line. |
| [`uji.input.append(text)`](input.md#ujiinputappendtext) | Adds text to the end of the input line. |
| [`uji.input.clear()`](input.md#ujiinputclear) | Empties the input line. |
| [`uji.input.attach(path)`](input.md#ujiinputattachpath) | Attaches an image file to the message on the input line. |
| [`uji.input.capture(handler)`](input.md#ujiinputcapturehandler) | Sends every key press to `handler` instead of the normal bindings, until `uji.input.release` runs. |
| [`uji.input.release()`](input.md#ujiinputrelease) | Returns the keyboard to the normal bindings. |

## Models

| Name | Does |
|---|---|
| [`uji.model.current()`](model.md#ujimodelcurrent) | Returns the provider, model, API root and effort the next turn uses. |
| [`uji.model.use(opts)`](model.md#ujimodeluseopts) | Changes the provider, model, API root or effort, and saves the choice. |
| [`uji.model.efforts()`](model.md#ujimodelefforts) | Returns the reasoning efforts the current model accepts. |

## Providers

| Name | Does |
|---|---|
| [`uji.provider.add(spec)`](provider.md#ujiprovideraddspec) | Adds a provider, or merges `spec` into the provider with the same `id`. |
| [`uji.provider.remove(id)`](provider.md#ujiproviderremoveid) | Removes a provider and returns `true` if it existed. |
| [`uji.provider.list()`](provider.md#ujiproviderlist) | Returns one table per provider with its settings and models. |
| [`uji.auth.configure(opts)`](auth.md#ujiauthconfigureopts) | Chooses between `auth.toml` and the system keychain for API keys and sign-ins. |
| [`uji.auth.authenticated(id)`](auth.md#ujiauthauthenticatedid) | Returns `true` when uji has a key or sign-in for a provider. |
| [`uji.auth.save_key(id, key)`](auth.md#ujiauthsave_keyid-key) | Saves an API key for a provider. |
| [`uji.auth.login(id, on_done)`](auth.md#ujiauthloginid-on_done) | Signs in to a provider with its subscription in the browser. |

## Provider APIs

| Name | Does |
|---|---|
| [`uji.class(parent)`](apis.md#ujiclassparent) | Makes a class, optionally from a parent class whose methods it keeps. |
| [`uji.api.openai`, `uji.api.responses`, `uji.api.anthropic`, `uji.api.gemini`](apis.md) | The API classes a provider's `api` is made from. |
| [`uji.api.stream.run(spec, reply)`](apis.md#ujiapistream) | Sends a request to a streaming endpoint and reads the events into an answer. |

## Processes

| Name | Does |
|---|---|
| [`uji.job.start(opts)`](job.md#ujijobstartopts) | Starts a process and returns a job table. |

## HTTP

| Name | Does |
|---|---|
| [`uji.http.request(opts, on_done)`](http.md#ujihttprequestopts-on_done) | Sends an HTTP request and returns a function that cancels it. |

## Files

| Name | Does |
|---|---|
| [`uji.fs.read(path, on_done)`](fs.md#ujifsreadpath-on_done) | Reads a whole file. |
| [`uji.fs.lines(path, opts, on_done)`](fs.md#ujifslinespath-opts-on_done) | Reads a range of lines from a text file. |
| [`uji.fs.write(path, content, on_done)`](fs.md#ujifswritepath-content-on_done) | Writes a file, creating missing directories. |
| [`uji.fs.list(path, on_done)`](fs.md#ujifslistpath-on_done) | Lists a directory. |
| [`uji.config.files(folder, opts, on_done)`](config.md#ujiconfigfilesfolder-opts-on_done) | Reads the files in a folder of your config, your packs and, if asked, the project. |

## JSON

| Name | Does |
|---|---|
| [`uji.json.encode(value)`](json.md#ujijsonencodevalue) | Turns a Lua value into a JSON string. |
| [`uji.json.decode(text, opts)`](json.md#ujijsondecodetext-opts) | Turns a JSON string into a Lua value. |
| [`uji.json.array(table)`](json.md#ujijsonarraytable) | Marks a table as a JSON array, so it encodes as `[]` even when empty. |

## Packs

| Name | Does |
|---|---|
| [`uji.pack.add(specs)`](pack.md#ujipackaddspecs) | Installs and loads packs. |
| [`uji.pack.list()`](pack.md#ujipacklist) | Returns every directory uji searches for modules and `plugin/` files, starting with your config directory. |
| [`uji.pack.update()`](pack.md#ujipackupdate) | Pulls every installed git pack and records the new commits in the lock file. |

## Timers and notices

| Name | Does |
|---|---|
| [`uji.schedule(callback)`](timers.md#ujischedulecallback) | Runs `callback` once the code that called it has finished. |
| [`uji.defer(seconds, callback)`](timers.md#ujideferseconds-callback) | Runs `callback` after a delay and returns a function that cancels it. |
| [`uji.notify(message)`](timers.md#ujinotifymessage) | Shows a notice in the transcript. |

## Quitting and reloading

| Name | Does |
|---|---|
| [`uji.quit()`](app.md#ujiquit) | Exits uji. |
| [`uji.reload()`](app.md#ujireload) | Restarts uji on the same session with your config read again. |

## Runtime

| Name | Does |
|---|---|
| [`uji.task.spawn(fn, ...)`](../runtime/tasks.md#ujitaskspawnfn-) | Starts a function as a task that runs alongside the rest of uji. |
| [`uji.sleep(seconds)`](../runtime/tasks.md#ujisleepseconds) | Pauses the current task. |
| [`uji.task.race(fn, ...)`](../runtime/tasks.md#ujitaskracefn-) | Runs functions at once and returns the first to finish. |
| [`uji.task.timeout(seconds, fn)`](../runtime/tasks.md#ujitasktimeoutseconds-fn) | Runs a function with a time limit. |
| [`uji.promise()`](../runtime/tasks.md#ujipromise) | Returns a promise that tasks can wait on. |
| [`uji.net.request(opts)`](../runtime/network.md#ujinetrequestopts) | Sends an HTTP request and returns the answer. |
| [`uji.net.open(opts)`](../runtime/network.md#ujinetopenopts) | Sends an HTTP request and streams the answer. |
| [`uji.net.listen(port)`](../runtime/network.md#ujinetlistenport) | Accepts connections on a local port. |
| [`uji.proc.spawn(argv, opts)`](../runtime/processes.md#ujiprocspawnargv-opts) | Starts a process. |
| [`uji.db.open(path)`](../runtime/storage.md#ujidbopenpath) | Opens a SQLite database. |
| [`uji.os`](../runtime/system.md) | Reads the platform, the environment and the clock. |
| [`uji.modules(namespace)`](../runtime/system.md#ujimodulesnamespace) | Lists the modules inside a namespace. |
| [`uji.keychain`](../runtime/system.md#ujikeychaingetservice-account) | Reads and writes secrets in the system keychain. |
| [`uji.clipboard`](../runtime/system.md#ujiclipboardget) | Reads and writes the system clipboard, and reads images from it. |
| [`uji.regex(pattern)`](../runtime/text.md#ujiregexpattern) | Compiles a regular expression. |
| [`uji.glob(pattern, opts)`](../runtime/text.md#ujiglobpattern-opts) | Compiles a glob. |
| [`uji.fuzzy(query, items)`](../runtime/text.md#ujifuzzyquery-items) | Ranks strings against a query. |
| [`uji.markdown(source)`](../runtime/text.md#ujimarkdownsource) | Parses Markdown into events. |
| [`uji.width(text)`](../runtime/text.md#ujiwidthtext) | Measures text in terminal columns. |
| [`uji.lossy(data)`](../runtime/text.md#ujilossydata) | Turns bytes into valid UTF-8. |
| [`uji.base64`](../runtime/encoding.md) | Encodes and decodes base64. |
| [`uji.toml`](../runtime/encoding.md) | Reads and writes TOML. |
| [`uji.sha256(data)`](../runtime/encoding.md) | Hashes data. |
| [`uji.random(count)`](../runtime/encoding.md) | Returns random bytes. |
| [`uji.image.fit(data, edge, bytes)`](../runtime/images.md#ujiimagefitdata-edge-bytes) | Checks an image and fits it to a size and a byte limit. |
