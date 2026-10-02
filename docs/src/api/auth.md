# uji.auth

These functions choose where credentials live, save them, and sign in to the
providers that offer a subscription.

## uji.auth.configure(opts)

Chooses where uji keeps API keys and subscription sign-ins.

| Field | Type | Meaning |
|---|---|---|
| `keychain` | boolean | With `true`, uji saves credentials in the system keychain and looks there first. The default is `false`. |

Without the keychain, uji keeps credentials in `auth.toml` in the
[data directory](../configuration/files.md), readable only by you. Each
provider gets a table named by its id, and a provider can also be a plain
string, which uji reads as an API key. A keychain that refuses a save sends
the credential to `auth.toml` as well.

Raises an error for an unknown field, and for a `keychain` that is not a
boolean.

## uji.auth.authenticated(id)

Returns `true` when uji has a saved key or sign-in for the provider `id`, or
finds its key in one of the provider's `auth_env` variables. Raises an error
for an unknown provider.

```lua
if not uji.auth.authenticated("anthropic") then
  uji.notify("run /login to set up Anthropic")
end
```

## uji.auth.save_key(id, key)

Saves an API key for the provider `id` and returns `true`, or `nil` and an
error message when the key could not be saved. Raises an error for an unknown
provider or an empty key.

```lua
local ok, err = uji.auth.save_key("openrouter", os.getenv("MY_OPENROUTER_KEY"))
```

## uji.auth.login(id, on_done)

Signs in to the provider `id` with its subscription. uji opens your browser,
waits for the sign-in to finish, saves it, and gives `true`, or `nil` and an
error message. A provider without `oauth` settings gives an error message
too. Raises an error for an unknown provider.

```lua
uji.auth.login("anthropic", function(ok, err)
  uji.notify(ok and "signed in" or "sign-in failed: " .. err)
end)
```
