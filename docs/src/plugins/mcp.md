# mcp

Tools from MCP servers, over stdio or HTTP.

```lua
require("mcp").setup({
  servers = {
    files = { cmd = { "npx", "-y", "@modelcontextprotocol/server-filesystem", "." } },
    linear = { url = "https://mcp.linear.app/mcp" },
  },
})
```

A server has `cmd` and optional `cwd`, or `url` and optional `token`. Its
tools are named `server__tool`, and each call asks you first unless your
[policy](../api/tool.md#ujitoolpolicyrules-opts) allows it. `/mcp add URL` connects a
server and signs you in when it asks, `/mcp remove` disconnects one, and
`/mcp` lists them.
