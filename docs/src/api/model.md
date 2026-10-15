# uji.model

These functions read and change the provider and model that uji sends turns
to, the reasoning effort it asks for, and the decisions it asks a provider for.
`/models`, `/effort` and `/login` use them.

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

## uji.model.decide(opts)

Asks a decision model how likely yes is the answer to each question about one
state, from 0 to 1. Returns `{ probabilities, calibrated }`, with a number for
each question it could answer, or `nil` and a `{ kind, message }` failure.
`calibrated` is `true` when a provider that answers decisions itself answered,
and `false` when uji asked the model in use over chat. The `jev` provider
answers decisions.

| Field | Type | Meaning |
|---|---|---|
| `state` | string or table | What the questions are about. A list of strings joins as paragraphs. |
| `questions` | table | Instructions per question id, each a string. |
| `provider` | string | The provider to ask. The provider in use by default. |
| `model` | string | The model to ask. The provider's first model by default, and the API's own default when the provider lists no model. |
| `timeout` | number | Seconds for the whole answer, including the provider's own retries. |
