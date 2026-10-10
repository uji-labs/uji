# websearch

`web_search` and `web_fetch` tools. Both go through Exa's public search
service, so they need no key. The free service is rate limited, though; with a
key from [Exa](https://dashboard.exa.ai/api-keys) in `EXA_API_KEY`, or in the
`key` option, the limit goes away.

```lua
require("websearch").setup({ count = 8 })
```

| Option | Meaning | Default |
|---|---|---|
| `policy` | Whether the tools ask before they run: `"allow"`, `"ask"` or `"deny"`. | `"allow"` |
| `count` | Results per search. | `5` |
| `chars` | Characters of a page that `web_fetch` returns at most. | `20000` |
| `timeout` | Seconds per request. | `30` |
| `key` | An Exa API key. | `EXA_API_KEY` |
