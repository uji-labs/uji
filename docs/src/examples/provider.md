# A provider

## An OpenAI-compatible endpoint

A LiteLLM proxy on your machine, or any server that speaks the OpenAI chat
format.

```lua
uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = os.getenv("LITELLM_BASE_URL") or "http://localhost:4000",
  auth_env = { "LITELLM_API_KEY" },
  models = {
    { id = "claude-sonnet-4-5", context = 1000000, output = 64000, reasoning = true },
    { id = "glm-4.6", context = 204800, output = 131072, reasoning = true },
  },
})
```

## An endpoint with its own quirks

Some differences need only an option. This server wants the output limit in
`max_completion_tokens`:

```lua
uji.provider.add({
  id = "gateway",
  name = "Gateway",
  api = uji.api.openai({ max_tokens_field = "max_completion_tokens" }),
  base_url = "https://gateway.example.com/v1",
  auth_env = { "GATEWAY_API_KEY" },
  models = { { id = "qwen3-coder", reasoning = true, efforts = { "off", "high" } } },
})
```

For anything else, make a class from the API and redefine the method that
differs. This server turns thinking on and off with `enable_thinking`:

```lua
local Qwen = uji.class(uji.api.openai)

function Qwen:thinking(body, request)
  body.enable_thinking = request.effort ~= "off"
end

uji.provider.add({
  id = "dashscope",
  name = "DashScope",
  api = Qwen(),
  base_url = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  auth_env = { "DASHSCOPE_API_KEY" },
  models = { { id = "qwen3-max", reasoning = true, efforts = { "off", "high" } } },
})
```

[Provider APIs](../api/apis.md) lists the options and methods of each API.

## Reading model sizes from the endpoint

A LiteLLM proxy reports each model's context and output limits at
`/model/info`. This plugin reads them when uji starts and corrects the models
the provider lists. It sends back each model whole, with its `reasoning` and
other fields, because `uji.provider.add` replaces a model with the same `id`
as a whole.

```lua
local BASE_URL = os.getenv("LITELLM_BASE_URL") or "http://localhost:4000"

uji.provider.add({
  id = "litellm",
  name = "LiteLLM",
  api = uji.api.openai(),
  base_url = BASE_URL,
  auth_env = { "LITELLM_API_KEY" },
  models = {
    { id = "claude-sonnet-4-5", reasoning = true },
  },
})

local function listed(id)
  for _, provider in ipairs(uji.provider.list()) do
    if provider.id == id then
      local models = {}
      for _, model in ipairs(provider.models) do
        models[model.id] = model
      end
      return models
    end
  end
  return {}
end

uji.http.request({
  url = BASE_URL .. "/model/info",
  headers = { Authorization = "Bearer " .. (os.getenv("LITELLM_API_KEY") or "") },
}, function(response)
  if not response or response.status ~= 200 then
    return
  end
  local ok, info = pcall(uji.json.decode, response.body, { nulls = false })
  if not ok or type(info) ~= "table" or type(info.data) ~= "table" then
    return
  end
  local known, changed = listed("litellm"), {}
  for _, entry in ipairs(info.data) do
    local model = known[entry.model_name]
    local limits = entry.model_info or {}
    if model and (limits.max_input_tokens or limits.max_output_tokens) then
      model.context = limits.max_input_tokens or model.context
      model.output = limits.max_output_tokens or model.output
      changed[#changed + 1] = model
    end
  end
  if #changed > 0 then
    uji.provider.add({ id = "litellm", models = changed })
    uji.emit("status_changed", {})
  end
end)
```

## Changing a built-in provider

With the id of a built-in provider, `uji.provider.add` changes only the fields
you give.

```lua
uji.provider.add({ id = "openai", base_url = "https://llm-proxy.internal/v1" })

uji.provider.add({
  id = "anthropic",
  models = { { id = "claude-fable-5-1", context = 1000000, output = 128000, reasoning = true } },
})
```
