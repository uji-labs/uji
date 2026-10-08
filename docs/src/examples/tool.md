# A tool of your own

Put these tools in `~/.config/uji/plugin/tools.lua`, or in `init.lua`.

## A tool that answers at once

`run` returns the result as a string.

```lua
uji.tool.add("branch", {
  description = "Name of the current git branch.",
  parameters = { type = "object", properties = {} },
  policy = "allow",
  display = { label = "Branch" },
  run = function()
    return io.popen("git branch --show-current"):read("*l") or "not a git repository"
  end,
})
```

## A tool that waits on a process

`run` starts a job and returns `job.stop`, so an interrupt kills it. The job
calls `ctx.done` when it exits.

```lua
uji.tool.add("count_todos", {
  description = "Count TODO comments per file in the working directory.",
  parameters = { type = "object", properties = {} },
  policy = "allow",
  display = { label = "TODOs" },
  run = function(_, ctx)
    local lines = {}
    local job = uji.job.start({
      cmd = { "rg", "--count-matches", "TODO" },
      on_stdout = function(line)
        lines[#lines + 1] = line
        ctx.progress(line)
      end,
      on_exit = function(code)
        if code == 1 then
          ctx.done("no TODO comments")
        else
          ctx.done(table.concat(lines, "\n"))
        end
      end,
    })
    return job.stop
  end,
})
```

## A tool with arguments and a subject

`subject` returns the URL, so the approval question shows it and the policy
matches it.

```lua
uji.tool.add("fetch_url", {
  description = "Download a web page and return its body.",
  parameters = {
    type = "object",
    properties = { url = { type = "string", description = "The page to fetch." } },
    required = { "url" },
  },
  subject = function(args)
    return args.url
  end,
  policy = "ask",
  display = { label = "Fetch", question = "Fetch this page?" },
  run = function(args, ctx)
    return uji.http.request({ url = args.url }, function(response, err)
      if not response then
        ctx.done("error: " .. err)
      else
        ctx.done(response.body:sub(1, 20000))
      end
    end)
  end,
})

uji.tool.policy({
  fetch_url = { allow = { "https://docs.rs/*" } },
})
```
