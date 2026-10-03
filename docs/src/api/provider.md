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
| `base_url` | string | The API root, such as `"https://api.openai.com/v1"`. Required for a new provider. |
| `auth_env` | list of strings | Environment variables that may hold the API key. |
| `models` | list | Model ids, or tables with `id`, `context`, `output`, `reasoning`, `cache`, `images` and `efforts`. `images` is `true` or `false` when you know whether the model takes images. `efforts` lists the reasoning efforts the model accepts, from `off`, `minimal`, `low`, `medium`, `high`, `xhigh` and `max`. Without it, uji asks the provider's `api`. |
| `context_window` | integer | The context size to assume for a model that does not set one. |
| `oauth` | table | Subscription sign-in settings. The built-in Anthropic and OpenAI providers show the format. |

When the provider exists, each field you give replaces the old one, except
`models`, which merge by `id`. A model whose `id` is already listed replaces
the old one whole.

Raises an error for an unknown field, for an `api` without a `stream` method,
for an unknown effort, and for a new provider without `name`, `api` and
`base_url`.

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
```

## OpenCode Go

Run `/login`, select **OpenCode Go**, and enter your OpenCode console API key.
You can also set `OPENCODE_API_KEY`.
The provider uses `https://opencode.ai/zen/go/v1`, separate from OpenCode Zen.
The provider file fetches available IDs from `/models` and capabilities from `https://models.dev/api.json`, then registers them with `uji.provider.add`.
Fetching runs in a background task after provider registration.
Execution waits for that task when the selected model is not already configured, before capturing reasoning effort, output limits, and caching.
Explicit model and effort choices remain selected while metadata loads.
No API key is sent to either public discovery request.
Failed requests produce an empty catalog and an inference error with the loading failure; use `/reload` to retry.
There is no bundled or stale catalog fallback.
Only models with metadata and documented endpoint assignments are listed.
It routes these models through the existing Chat Completions, Anthropic Messages, or Responses APIs.

Zen fetches its own inventory and uses separate endpoint assignments, including Gemini.
Client and owning-session headers apply to both services, including title and compaction requests.
HTTP rejection messages include bounded server details with outgoing API keys redacted.
An HTTP 403 does not establish that your API key is invalid.

Model availability and subscription allowances depend on your account.
Context and output token limits do not represent remaining subscription allowance.
Disable **Use balance** in the Go console if you do not want account-enabled pay-as-you-go fallback.
Go API-key access does not configure ChatGPT subscription authentication.

## uji.provider.remove(id)

Removes a provider and returns `true` if it existed.

```lua
uji.provider.remove("perplexity")
```

## uji.provider.list()

Returns one table per provider with `id`, `name`, `api`, `base_url`,
`auth_env`, `context_window` and `models`, and `oauth`, which is `true` when
the provider offers subscription sign-in. Each model has `id`, `context`,
`output`, `reasoning`, `cache`, `images` and `efforts`.

```lua
for _, provider in ipairs(uji.provider.list()) do
  if provider.base_url:find("localhost", 1, true) then
    uji.notify(provider.name)
  end
end
```
