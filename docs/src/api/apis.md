# Provider APIs

A provider's `api` turns a model call into a request in one HTTP API's format
and streams the answer back. It's an object with a `stream` method, and you set it with
the `api` field of [`uji.provider.add`](provider.md#ujiprovideraddspec).

uji ships four API classes under `uji.api`, and calling a class makes an
object.

| Class | API |
|---|---|
| `uji.api.openai` | OpenAI Chat Completions, `/chat/completions`. Most providers use it. |
| `uji.api.responses` | OpenAI Responses, `/responses`. The OpenAI and xAI providers use it. |
| `uji.api.anthropic` | Anthropic Messages, `/messages`. |
| `uji.api.gemini` | Gemini `streamGenerateContent`. |

`uji.api.<name>` loads `lua/uji/builtin/apis/<name>.lua`, so a file of your
own in that folder of your config adds `uji.api.<name>` too.

```lua
uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = "http://localhost:4000",
  auth_env = { "LITELLM_API_KEY" },
  models = { { id = "claude-sonnet-4-5", reasoning = true } },
})
```

## uji.class(parent)

Makes a class from `parent`, such as `uji.api.openai`, that keeps the parent's
methods until it defines its own. The next section shows it in use.

## Changing an API for one provider

A provider whose API differs in a few places gets a class of its own, made
from the closest built-in class with `uji.class`. It redefines only the
methods that differ. This is how the built-in DeepSeek provider turns
thinking on and off and sends each reply's reasoning back:

```lua
local OpenAI = uji.api.openai

local DeepSeek = uji.class(OpenAI)

function DeepSeek:efforts()
  return { "off", "low", "high", "max" }
end

function DeepSeek:thinking(body, request)
  body.thinking = { type = request.effort == "off" and "disabled" or "enabled" }
  if request.effort ~= "off" then
    body.reasoning_effort = request.effort
  end
end

function DeepSeek:assistant(item, request)
  local out = OpenAI.assistant(self, item, request)
  out.reasoning_content = item.reasoning or ""
  return out
end

uji.provider.add({
  id = "deepseek",
  name = "DeepSeek",
  api = DeepSeek(),
  base_url = "https://api.deepseek.com",
  models = { { id = "deepseek-v4-pro", reasoning = true } },
})
```

## The OpenAI Chat Completions class

`uji.api.openai(opts)` makes an object. Each field of
`opts` is set on the object, so these options can be given there or changed
in a class of your own.

| Option | Default | Meaning |
|---|---|---|
| `max_tokens_field` | `"max_tokens"` | The body field for the output limit, such as `"max_completion_tokens"`. `false` leaves the limit out. |
| `finish_reason` | `true` | With `false`, a stream that ends without a `finish_reason` still counts as complete. |
| `cache_key` | `false` | With `true`, sends the session id as `prompt_cache_key`. |
| `tool_result_name` | `false` | With `true`, sends the tool's name with each tool result. |
| `bridge_tool_images` | `false` | With `true`, puts a short assistant message between tool results and the images they returned. Mistral needs this. |

These methods are the ones a provider most often redefines:

| Method | Does |
|---|---|
| `efforts(model)` | Returns the efforts a model accepts, used when the model does not list its own. |
| `thinking(body, request)` | Adds the reasoning fields to the request body. The default sends `reasoning_effort`. |
| `user(item, request)`, `assistant(item, request)`, `tool(item, request)` | Turn one message into the API's format. |
| `headers(request)` | Returns the request headers. The default sends the key as a bearer token. |
| `url(request)` | Returns the endpoint. |
| `body(request)` | Builds the whole request body. |
| `reasoning(delta)` | Returns the reasoning text in a streamed delta. The default reads `reasoning_content`, `reasoning` and `reasoning_text`. |

The other classes follow the same shape. The Responses class has the
`cache_key` option, on by default, and a `reasoning(request)` method that
returns the `reasoning` field. The Anthropic class picks adaptive thinking or
a thinking budget from the model id, and the Gemini class picks a thinking
level or a budget the same way.

## The request

An API can define `ready(model)` when it loads model metadata asynchronously.
Return `true` when loading completes, or `nil, failure` when it fails.
Uji waits for this method before capturing turn capabilities or preparing an auxiliary request.
Configuration and model selection do not wait, so start asynchronous loading with `uji.schedule`, outside `require()`.

uji calls `api:stream(request, reply)`. The method may return a function that
cancels the call. The request has these fields:
- `model`, the model id
- `system`, the system prompt
- `messages`, the conversation in uji's message format, where a user or tool
  message may have `images`, a list of tables with `media_type`, base64
  `data`, `name`, `width` and `height`
- `tools`, a list of `name`, `description` and `parameters`
- `reasoning`, `true` when the model reasons
- `effort`, one of the model's efforts, or `nil` for the provider's default
- `max_output`, the output token limit
- `cache`, one of `off`, `short` and `long`
- `session`, the session id
- `provider`, with `id` and `base_url`
- `auth`, with `key`, and `oauth` for subscription sign-in

An assistant message carries the `replay` its API returned, described below.

## The reply

The reply table has four functions:
- `reply.text(delta)` streams answer text.
- `reply.reasoning(delta)` streams reasoning text.
- `reply.done(answer)` finishes the call. `answer` has `text`, and optionally
  `reasoning`, `tool_calls`, `usage` and `replay`. Each tool call has `id`,
  `name` and `arguments`, where `arguments` is a JSON string, and may have a
  `signature`. `usage` has `input`, `output`, `cache_read` and `cache_write`.
- `reply.fail(failure)` ends the call with an error. `failure.kind` is
  `"http"`, with `status`, `message` and `retry_after`, or `"auth"`, with
  `status`, or `"provider"`, with `message`. uji retries `http` failures with a
  status of 408, 409, 425, 429 or 5xx, and `http` failures with no status,
  such as a dropped connection.

## Replay

Some APIs need data from an earlier reply sent back with the conversation,
such as Anthropic's signed thinking blocks or the encrypted reasoning of the
Responses API. An API puts that data in `answer.replay`, and uji saves it on
the assistant message. When the API builds a later request, it finds the data
in `item.replay` and sends it back. The built-in classes tag their replay with
their name and the model, and send it back only to the same model. A
tool call's `signature` is saved the same way, and the Gemini class sends it
back with the call.

## uji.api.stream

`uji.api.stream.run(spec, reply)` sends a JSON `POST` to
an endpoint that answers with server-sent events, reads the stream into an
answer, and ends the call through `reply`. It returns the answer, or `nil`
and the failure, so a `stream` method can return what it returns. The
built-in classes all use it.

| Field | Type | Meaning |
|---|---|---|
| `url` | string | Required. The endpoint. |
| `headers` | table | Request headers. uji adds `Content-Type: application/json`. |
| `body` | table | The request body, which uji encodes as JSON. |
| `read` | function | Required. uji calls `read(event, parts)` with each `data:` event, decoded from JSON. |
| `finished` | function | Called as `finished(parts)` when the stream ends. It may return a failure. |
| `settle` | function | Called as `settle(parts, calls)` once the tool calls are complete. It may return a failure. |

`read` builds the answer on `parts`:
- `parts:push_text(delta)` adds answer text and streams it to the transcript.
- `parts:push_reasoning(delta)` does the same for reasoning text.
- `parts:call(index)` returns the tool call at `index`, creating it with an
  empty `id`, `name` and `arguments`. Set `id` and `name`, and append each
  fragment of JSON to `arguments` as it arrives. A `signature` set on it stays
  with the call.
- `parts:finish()` marks the reply as complete. A `data: [DONE]` line does the
  same.
- `parts.usage` is a table with `input`, `output`, `cache_read` and
  `cache_write`, which `read` sets from what the provider reports.
- `parts.hit_limit = true` records that the model stopped at its output limit.
- `parts.failure` set to a failure ends the call with it.
- `parts.replay` becomes the answer's `replay`.
- `parts:has_text()` returns `true` once any answer text has arrived.

uji ends the call with a failure in these cases:
- The status is not 2xx. A 401 or 403 is an `auth` failure, and anything else
  is an `http` failure with the status, the `retry-after` seconds and the
  start of the body.
- No data arrives for 120 seconds.
- The stream ends before `parts:finish()`. A provider that never says it
  finished can call `parts:finish()` from `finished`.
- A tool call's `arguments` are not complete JSON.
- The model hit its output limit and made no tool calls.

```lua
local Plain = uji.class()

function Plain:stream(request, reply)
  local messages = { { role = "system", content = request.system } }
  for _, message in ipairs(request.messages) do
    if message.type == "user" or message.type == "assistant" then
      messages[#messages + 1] = { role = message.type, content = message.text }
    end
  end
  return uji.api.stream.run({
    url = request.provider.base_url .. "/chat/completions",
    headers = { Authorization = "Bearer " .. (request.auth.key or "") },
    body = { model = request.model, messages = messages, stream = true },
    read = function(event, parts)
      local choice = event.choices and event.choices[1]
      if choice and choice.delta and choice.delta.content then
        parts:push_text(choice.delta.content)
      end
      if choice and choice.finish_reason then
        parts.hit_limit = choice.finish_reason == "length"
        parts:finish()
      end
    end,
  }, reply)
end

uji.provider.add({ id = "plain", name = "Plain", api = Plain(), base_url = "http://localhost:8080/v1" })
```
