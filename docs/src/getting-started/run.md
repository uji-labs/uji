# Running a prompt without the screen

`uji run` sends one prompt, lets the model work until it answers, prints the
answer and exits. Scripts and other programs use it, and so do the agents of
the [subagent](../plugins/subagent.md) plugin. It reads the same config,
plugins and packs as uji does on the screen, and saves the conversation as a
session.

```sh
uji run "Summarise what changed in the last commit"
```

The words after the options form the prompt. The exit code is `0` when the
model answers and `1` when the turn fails, with the reason on standard error.

| Option | Does |
|---|---|
| `--json` | Prints every event as a line of JSON instead of the answer alone. |
| `--model <PROVIDER/ID>` | Uses this model instead of the one you picked with `/models`. |
| `--effort <LEVEL>` | Uses this reasoning effort: `off`, `minimal`, `low`, `medium`, `high`, `xhigh` or `max`. uji uses the nearest level the model accepts. |
| `--tools <A,B>` | Offers the model only these tools, separated by commas. |
| `--append-prompt <TEXT>` | Adds the text to the end of the system prompt. |
| `--title <TEXT>` | Titles the session. The default is the first line of the prompt. |
| `--parent <ID>` | Saves the session under another one. `uji list` leaves it out, and `uji resume --id` opens it. |

Nobody can answer an approval question here, so a call your
[policy](../api/tool.md#ujitoolpolicyrules) would ask about runs without
asking. Calls your policy denies stay denied.

The options `--config-dir`, `--data-dir` and `--db` work as they do for the
other commands.

## JSON events

With `--json`, each line is one event.

| `type` | Fields | When |
|---|---|---|
| `session` | `id` | First, with the id of the new session. |
| `message` | `message` | A message joined the conversation, in the form uji saves it. |
| `progress` | `tool`, `line` | A running tool printed a line. |
| `notice` | `text` | uji has something to tell you, such as a plugin error. |
| `done` | `text` or `error`, and `usage` | Last. `usage` has `input`, `output`, `cache_read` and `cache_write` tokens for the whole run. |

```sh
uji run --json --tools read_file "What does src/main.rs do?" | jq -r 'select(.type == "done") | .text'
```
