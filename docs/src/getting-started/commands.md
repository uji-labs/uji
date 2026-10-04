# Commands

## Running uji

| Run | Does |
|---|---|
| `uji`, `uji new` | Starts a new session. |
| `uji resume` | Resumes the latest session with history in the current directory. |
| `uji resume --id <ID>` | Resumes the session with that id. |
| `uji list` | Opens a picker of the sessions in the current directory. |
| `uji delete <ID>` | Deletes a session. |
| `uji run <PROMPT>` | Sends one prompt without the screen and prints the answer. See [Running without the screen](run.md). |
| `uji --help` | Prints the usage. |
| `uji --version` | Prints the version. |

Any of them takes these options. [Where uji keeps its files](../configuration/files.md)
lists the environment variables that do the same.

| Option | Sets |
|---|---|
| `--config-dir <DIR>` | The config directory. |
| `--data-dir <DIR>` | The data directory. |
| `--db <FILE>` | The session database. |

## Slash commands

| Command | Does |
|---|---|
| `/login` | Adds a provider. |
| `/models` | Picks the model. |
| `/sessions` | Resumes or deletes a saved conversation in the current directory. |
| `/new` | Starts a fresh conversation and carries your text draft. Pending work or draft images block the switch. |
| `/effort` | Sets the reasoning effort, from the levels the current model accepts. |
| `/thinking` | Shows or hides the model's reasoning. |
| `/compact` | Summarises earlier messages to free context. |
| `/sync` | Updates installed packs and reloads. |
| `/reload` | Starts uji again with your current config and files, keeping the conversation and your draft. |
| `/help` | Lists every command, including the ones plugins add. |
| `/quit` | Quits. |

## Keys

[Default bindings](../api/keymap.md#default-bindings) lists every key uji
binds, and [uji.keymap](../api/keymap.md) changes them.
