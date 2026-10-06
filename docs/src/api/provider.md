# uji.provider

uji ships 22 providers, and `/login` and `/models` offer every one you add
here as well.

## uji.provider.add(spec)

Adds a provider, or merges `spec` into the provider with the same `id`.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Required. The provider's id. |
| `name` | string | The name `/login` shows. Required for a new provider. |
| `api` | object | The API the provider speaks, such as `uji.api.openai()`. [Provider APIs](apis.md) lists the built-in ones and how to change them. Required for a new provider. |
| `loop` | class | Runs the turn instead of uji's own loop, for a provider that runs the model and the tools itself, such as a coding agent CLI. See [Your own loop](#your-own-loop). |
| `base_url` | string | The API root, such as `"https://api.openai.com/v1"`. Required for a new provider without a `loop`. |
| `auth_env` | list of strings | Environment variables that may hold the API key. |
| `models` | list or function | Model ids, or tables with `id`, `context`, `output`, `reasoning`, `cache`, `images` and `efforts`. `images` is `true` or `false` when you know whether the model takes images. `efforts` lists the reasoning efforts the model accepts, from `off`, `minimal`, `low`, `medium`, `high`, `xhigh` and `max`. Without it, uji asks the provider's `api`. A function returns that list, and uji calls it once, the first time it needs the provider's models. The function may wait, for example on `uji.http.request`. |
| `context_window` | integer | The context size to assume for a model that does not set one. |
| `oauth` | table | Subscription sign-in settings. The built-in Anthropic and OpenAI providers show the format. |

When the provider exists, each field you give replaces the old one, except
`models`, which merge by `id`. A model whose `id` is already listed replaces
the old one whole.

Raises an error for an unknown field, for an `api` without a `stream` method,
for a `loop` that is not a class with a `run` method, for `models` that are
neither a list nor a function, for an unknown effort, and for a new provider
that lacks `name` or `api`, or has neither `base_url` nor `loop`.

```lua
uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = "http://localhost:4000",
  auth_env = { "LITELLM_API_KEY" },
  models = {
    { id = "claude-sonnet-4-5", context = 200000, output = 64000, reasoning = true },
  },
})

uji.provider.add({ id = "openai", base_url = "https://proxy.example.com/v1" })

uji.provider.add({
  id = "ollama",
  models = function()
    local response = uji.http.request({ url = "http://localhost:11434/api/tags", timeout = 5 })
    local models = {}
    for _, entry in ipairs(uji.json.decode(response.body).models) do
      models[#models + 1] = entry.name
    end
    return models
  end,
})
```

uji calls the function when the provider is the current one, when `/models`
lists it, and before the first request to it. The models it returns merge
with the ones the provider already has. When it raises an error, the provider
keeps its models, and uji calls it again the next time it needs them.

## Your own loop

A provider with a `loop` runs each turn itself. When you send a message, uji
makes a loop with `Loop(agent, turn)` and calls `loop:run()` in a task.

`turn` holds:

| Field | Meaning |
|---|---|
| `prompt` | The message you sent, as a table with `text` and `images`. |
| `model`, `effort` | The model and reasoning effort in use. |
| `system` | The system prompt uji built. |
| `messages` | The session so far, in uji's own format. |
| `tools` | uji's tools. |
| `reasoning`, `max_output`, `cache` | Whether the model reasons, its output limit and the prompt cache setting. |

A loop that keeps its own history and runs its own tools can leave
`system`, `messages` and `tools` alone.

`run` must end the turn with `agent:done` or `agent:failed`. When `run`
returns without either, uji fails the turn with
`loop: the turn ended without an answer`, and when it raises, uji fails the
turn with `loop: ` and the error.

When you stop the turn, uji first stops the loop's task, then calls
`loop:interrupt()` if the loop has one. `interrupt` must return at once, so
anything that takes time, such as killing a process that does not quit, goes
in `uji.defer`.

The loop reports back through `agent`:

| Call | Meaning |
|---|---|
| `agent:delta(kind, text)` | Streams a piece of `"text"` or `"reasoning"` to the screen. |
| `agent:assistant_step(message)` | Stores an `assistant` message with `text`, `tool_calls` and `reasoning`, when the turn goes on after it. |
| `agent:tool_running(call)` | Names the call that runs now, so an interrupt can say so. |
| `agent:approve(name, arguments)` | Runs uji's approval: the tool policy, `before_tool` handlers and the question on screen. Returns `{ allow = true, arguments = ... }` or `{ deny = "reason" }`. |
| `agent:after_tool(name, content)` | Runs the `after_tool` handlers over a result. |
| `agent:tool_result(call, content, images)` | Stores a `tool` message for a call. |
| `agent:usage(spent)` | Adds `input`, `output`, `cache_read` and `cache_write` tokens to the session. |
| `agent:done(message)` | Stores the last `assistant` message and ends the turn. |
| `agent:failed(text)` | Stores an `error` message and ends the turn. |
| `agent:queued()` | Returns `true` when you sent more messages during the turn. |
| `agent:steer()` | Stores the next of those messages and returns it, or returns `nil`. If the loop never calls it, uji sends those messages as new turns once the turn is done. |

The provider still needs its `api`. uji asks it for the session's title and
for the reasoning efforts of models that do not list them. uji does not
compact the session of a provider with a loop, since the loop keeps its own
context, and `/compact` says so.

## uji.provider.remove(id)

Removes a provider and returns `true` if it existed.

```lua
uji.provider.remove("perplexity")
```

## uji.provider.list()

Returns one table per provider with `id`, `name`, `api`, `base_url`,
`auth_env`, `context_window`, `models`, `oauth`, which is `true` when the
provider offers subscription sign-in, `loop`, which is `true` when the provider
runs its own agent loop, `state` and `error`. Each model has `id`,
`context`, `output`, `reasoning`, `cache`, `images` and `efforts`.

`state` is one of the values in `uji.provider.STATE`:

| Value | Meaning |
|---|---|
| `STATE.IDLE` | The provider has a `models` function that uji has not called yet. |
| `STATE.LOADING` | The function is running. |
| `STATE.LOADED` | The models are in. A provider with a plain list starts here. |
| `STATE.FAILED` | The function raised an error, and `error` holds its message. uji calls it again the next time it needs the models. |

```lua
for _, provider in ipairs(uji.provider.list()) do
  if provider.base_url:find("localhost", 1, true) then
    uji.notify(provider.name)
  end
end
```

## uji.provider.get(id)

Returns the row for one provider, in the format `uji.provider.list()` uses, or
`nil` when no provider has that id. It does not load anything.

## uji.provider.load(id, on_done)

Calls the provider's `models` function if its models are not loaded yet,
waits for it, and returns the provider's row. The row's `state` is
`STATE.LOADED`, or `STATE.FAILED` with `error` set. With `on_done`, it returns
at once and calls `on_done` with the row. Raises an error when no provider has
that id.

```lua
local ollama = uji.provider.load("ollama")
if ollama.state == uji.provider.STATE.FAILED then
  uji.notify("could not list Ollama models: " .. ollama.error)
end
```
