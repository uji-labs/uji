# uji.model

These functions read and change the provider and model that uji sends turns
to, and the reasoning effort it asks for. `/models`, `/effort` and `/login` use them.

## uji.model.current()

Returns a table that describes what the next turn uses.

| Field | Meaning |
|---|---|
| `provider` | The provider's id, or `""` before one is set. |
| `name` | The provider's name, or `nil` before one is set. |
| `model` | The model id. |
| `base_url` | The API root the request goes to. |
| `effort` | The reasoning effort the next turn sends, or `nil` when the model does not reason. |
| `images` | `true` or `false` when uji knows whether the model takes images, and `nil` when it does not. |

```lua
local current = uji.model.current()
uji.notify(current.provider .. "/" .. current.model)
```

## uji.model.use(opts)

Changes the provider, model, API root or effort, saves the choice for the next
time uji starts, and fires [`model_changed`](events.md#model_changed).

| Field | Type | Meaning |
|---|---|---|
| `provider` | string | The id of the provider to switch to. |
| `model` | string | The model to use. Switching provider without a model picks the one you used last with that provider, or its first model. |
| `base_url` | string | An API root that overrides the provider's. `""` goes back to the provider's own. Switching provider clears it unless you give one. |
| `effort` | string | One of `off`, `minimal`, `low`, `medium`, `high`, `xhigh` and `max`. uji saves it, and each turn uses the nearest effort the current model accepts, so `medium` on a model that offers only `low` and `high` sends `high`. |

Fields you leave out stay as they are. Raises an error for an unknown provider
or effort.

```lua
uji.model.use({ provider = "anthropic", model = "claude-sonnet-4-5", effort = "high" })
```

## uji.model.efforts()

Returns the reasoning efforts the current model accepts, from the least
thinking to the most, such as `{ "off", "low", "medium", "high", "xhigh", "max" }`.
A model that does not reason gives an empty list. The model's `efforts` in
[`uji.provider.add`](provider.md#ujiprovideraddspec) set the list, and the
provider's API supplies it for a model without one.

```lua
local efforts = uji.model.efforts()
```
