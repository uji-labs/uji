# websearch

`web_search` and `web_fetch` tools, through one of two services.

```lua
require("websearch").setup({ count = 8 })
require("websearch").setup({ backend = "searxng", url = "http://localhost:8888" })
```

With `backend = "exa"`, the default, both go through Exa's public search service,
so they need no key. The free service is rate limited, though; with a key from
[Exa](https://dashboard.exa.ai/api-keys) in `EXA_API_KEY`, or in the `key`
option, the limit goes away.

With `backend = "searxng"`, `web_search` asks your own
[SearXNG](https://docs.searxng.org) instance, at `url` or `SEARXNG_URL`, and
`web_fetch` reads the page itself and turns its HTML into text. SearXNG answers
JSON only once it is allowed, under `search.formats` in its `settings.yml`:

```yaml
search:
  formats:
    - html
    - json
```

Its limiter expects a proxy in front that sets `X-Forwarded-For`, and blocks
requests that arrive without one. For an instance only you use, turn it off
with `server.limiter: false`, or give `url` the proxy's address rather than the
SearXNG container's.

| Option | Meaning | Default |
|---|---|---|
| `backend` | Where searches go: `"exa"` or `"searxng"`. Each is a module in `websearch/backend/`. | `"exa"` |
| `url` | The SearXNG instance, for `backend = "searxng"`. | `SEARXNG_URL` |
| `key` | An Exa API key, for `backend = "exa"`. | `EXA_API_KEY` |
| `policy` | Whether the tools ask before they run: `"allow"`, `"ask"` or `"deny"`. | `"allow"` |
| `count` | Results per search. | `5` |
| `chars` | Characters of a page that `web_fetch` returns at most. | `20000` |
| `timeout` | Seconds per request. | `30` |
