# uji.provider

uji ships 22 providers. `/login` and `/models` read this list, so a provider
you add shows up in both.

### uji.provider.add(spec)

Adds a provider, or merges `spec` into the provider with the same `id`.

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Required. The provider's id. |
| `name` | string | The name `/login` shows. Required for a new provider. |
| `wire` | string | The request format: `"openai-chat"`, `"anthropic"`, `"gemini"`, or one you added with [`uji.wire.add`](wire.md). Required for a new provider. |
| `base_url` | string | The API root, such as `"https://api.openai.com/v1"`. Required for a new provider. |
| `auth_env` | list of strings | Environment variables that may hold the API key. |
| `models` | list | Model ids, or tables with `id`, `context`, `output`, `reasoning` and `cache`. |
| `context_window` | integer | The context size to assume for a model that does not set one. |
| `compat` | table | Options for the wire, such as the name of the output limit field. On `openai-chat`, `cache_key = true` sends the session id as `prompt_cache_key`, which the OpenAI API uses to reuse its cache. It is on for `api.openai.com`. |
| `oauth` | table | Subscription sign-in settings. The built-in Anthropic and OpenAI providers show the format. |

When the provider exists, each field you give replaces the old one, except
`compat`, whose keys merge, and `models`, which merge by `id`.

Raises an error for an unknown field, and for a new provider without `name`,
`wire` and `base_url`.

```lua
uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  wire = "openai-chat",
  base_url = "http://localhost:4000",
  auth_env = { "LITELLM_API_KEY" },
  models = {
    { id = "claude-sonnet-4-5", context = 200000, output = 64000, reasoning = true },
  },
})

uji.provider.add({ id = "openai", base_url = "https://proxy.example.com/v1" })
```

### uji.provider.remove(id)

Removes a provider and returns `true` if it existed.

```lua
uji.provider.remove("perplexity")
```

### uji.provider.list()

Returns one table per provider with `id`, `name`, `wire`, `base_url` and
`models`. Each model has `id`, `context` and `output`.

```lua
for _, provider in ipairs(uji.provider.list()) do
  if provider.wire == "anthropic" then
    uji.notify(provider.name)
  end
end
```
