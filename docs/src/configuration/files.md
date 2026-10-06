# Where uji keeps its files

| Files | Default | Changed by |
|---|---|---|
| Config directory | `~/.config/uji` | `--config-dir`, `UJI_CONFIG_DIR` or `XDG_CONFIG_HOME` |
| Data directory | `~/.local/share/uji` | `--data-dir`, `UJI_DATA_DIR` or `XDG_DATA_HOME` |
| Session database | `uji.db` in the data directory | `--db` or `UJI_DB` |
| Installed packs | `site/` in the data directory | |
| Pack versions | `uji-lock.json` in the config directory | |
| Credentials | `auth.toml` in the data directory | [`uji.auth.configure`](../api/auth.md) |
| Diagnostics | `diagnostics.log` in the data directory | |

An option on the command line wins over the `UJI_` variable, which wins over
the `XDG_` one. uji adds `/uji` to the `XDG_` directories.
