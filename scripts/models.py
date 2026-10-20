#!/usr/bin/env python3
"""Refresh the provider model tables from https://models.dev/api.json.

Each managed provider file keeps everything but its `models` table. Entries
models.dev lists are rebuilt from its limits, reasoning and image flags; an
entry's own `cache` and `efforts` are carried over, and ids models.dev does
not list stay as written unless --prune is given.

    uv run scripts/models.py            # rewrite the files
    uv run scripts/models.py --check    # report, change nothing
    uv run scripts/models.py deepseek   # only these providers

`just models` runs it and formats the result.
"""

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROVIDERS = ROOT / "lua/uji/builtin/providers"
METADATA = "https://models.dev/api.json"
TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|[{},"]|[^{},"]+')

SOURCES = {
    "anthropic": "anthropic",
    "baseten": "baseten",
    "cerebras": "cerebras",
    "deepseek": "deepseek",
    "fireworks": "fireworks-ai",
    "google": "google",
    "groq": "groq",
    "huggingface": "huggingface",
    "mistral": "mistral",
    "moonshotai": "moonshotai",
    "nvidia": "nvidia",
    "openrouter": "openrouter",
    "perplexity": "perplexity",
    "together": "togetherai",
    "xai": "xai",
    "zai": "zai",
}

RETIRED = {
    "deepseek": {"deepseek-v4-flash", "deepseek-v4-flash-vision-exp"},
}

EFFORTS = {
    "none": "off",
    "off": "off",
    "minimal": "minimal",
    "low": "low",
    "medium": "medium",
    "high": "high",
    "xhigh": "xhigh",
    "max": "max",
}

UNMANAGED = {
    "openai": "its table uses effort constants and carries image and embedding models models.dev does not list",
    "github-copilot": "its models come from the authenticated Copilot API",
    "github-models": "GitHub Models is not models.dev's github-copilot",
    "custom": "it has no models",
    "jev": "its models come from its own api",
    "llamacpp": "its models come from the running server",
    "lmstudio": "its models are local",
    "ollama": "its models are local",
    "opencode-go": "its models come from opencode",
    "opencode-zen": "its models come from opencode",
}


def fetch():
    request = urllib.request.Request(METADATA, headers={"User-Agent": "uji", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def tokens(text):
    """The tokens of Lua source, blanks dropped."""
    return [token for token in TOKEN.findall(text) if token.strip()]


def atom(text):
    """The value a bare token spells."""
    if text in ("true", "false"):
        return text == "true"
    return int(text)


def value_at(stream, at):
    """The value at `at`, and the index after it."""
    token = stream[at]
    if token == "{":
        return constructor(stream, at)
    if token.startswith('"'):
        return json.loads(token), at + 1
    return atom(token), at + 1


def constructor(stream, at):
    """The value of the constructor at `at`, and the index after it."""
    fields = []
    items = []
    at += 1
    while stream[at] != "}":
        token = stream[at]
        if token == ",":
            at += 1
            continue
        if "=" in token and not token.startswith('"'):
            key, rest = (part.strip() for part in token.split("=", 1))
            value, at = (atom(rest), at + 1) if rest else value_at(stream, at + 1)
            fields.append((key, value))
        else:
            value, at = value_at(stream, at)
            items.append(value)
    return (dict(fields) if fields else items), at + 1


def models_span(text):
    """The offsets of the braces around the provider's models table."""
    stream = [match for match in TOKEN.finditer(text) if match.group(0).strip()]
    for index, match in enumerate(stream):
        if match.group(0).strip() != "models =":
            continue
        depth = 0
        for closing in stream[index + 1:]:
            if closing.group(0) == "{":
                depth += 1
            elif closing.group(0) == "}":
                depth -= 1
                if depth == 0:
                    return stream[index + 1].start(), closing.start()
    raise ValueError("no models table")


def entries(inner):
    """The models table's entries as (id, entry), in the order written."""
    found, _ = constructor(tokens("{" + inner + "}"), 0)
    return [(entry["id"] if isinstance(entry, dict) else entry, entry) for entry in found]


def tuning(entry):
    return {key: entry[key] for key in ("cache", "efforts") if key in entry}


def fields_for(info):
    limit = info.get("limit") or {}
    fields = {"id": info["id"]}
    for name in ("context", "output"):
        if limit.get(name):
            fields[name] = limit[name]
    if info.get("reasoning") is True:
        fields["reasoning"] = True
    inputs = (info.get("modalities") or {}).get("input") or []
    fields["images"] = "image" in inputs
    return fields


def levels_of(info):
    for option in info.get("reasoning_options") or []:
        if option.get("type") == "effort":
            levels = [EFFORTS[value] for value in option.get("values") or [] if value in EFFORTS]
            if len(levels) > 1:
                return {"efforts": levels}
    return {}


def rebuilt(id, current, info):
    have = {name: entry for name, entry in current if isinstance(entry, dict)}
    wanted = []
    for name in sorted(info):
        if name in RETIRED.get(id, set()):
            continue
        carried = tuning(have[name]) if name in have else levels_of(info[name])
        wanted.append((name, fields_for(info[name]) | carried))
    return wanted


def render(value):
    """The Lua source a value spells."""
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{key} = {render(item)}" for key, item in value.items()) + " }"
    if isinstance(value, list):
        return "{ " + ", ".join(render(item) for item in value) + " }"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    return str(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("providers", nargs="*", metavar="provider", help="only these provider files")
    parser.add_argument("--check", action="store_true", help="report what would change and exit 1 if anything would")
    parser.add_argument("--prune", action="store_true", help="drop ids models.dev does not list")
    args = parser.parse_args()

    metadata = fetch()
    changed = []
    for id in args.providers or sorted(SOURCES):
        if id in UNMANAGED:
            print(f"{id}: left alone, {UNMANAGED[id]}")
            continue
        if id not in SOURCES or SOURCES[id] not in metadata:
            print(f"{id}: no models.dev entry")
            continue
        path = PROVIDERS / (id + ".lua")
        text = path.read_text()
        start, end = models_span(text)
        inner = text[start + 1:end]
        info = {name: dict(model, id=name) for name, model in metadata[SOURCES[id]]["models"].items()}
        current = entries(inner)
        wanted = rebuilt(id, current, info)
        extra = [(name, entry) for name, entry in current if name not in info and name not in RETIRED.get(id, set())]
        if args.prune:
            for name, _ in extra:
                print(f"{id}: dropped {name}, models.dev does not list it")
        else:
            wanted += extra
        wanted.sort(key=lambda entry: entry[0])
        if wanted == current:
            continue
        changed.append(id)
        have = dict(current)
        names = dict(wanted)
        added = sum(1 for name, entry in wanted if have.get(name) != entry)
        gone = sum(1 for name in have if name not in names)
        print(f"{id}: {added} new or changed, {gone} gone" if added or gone else f"{id}: ordered")
        if args.check:
            continue
        first = next((line for line in inner.splitlines() if line.strip()), "")
        indent = first[: len(first) - len(first.lstrip())] or " " * 8
        close = inner[inner.rfind("\n") + 1:]
        lines = [render(entry) + "," for _, entry in wanted]
        block = "{" + "".join("\n" + indent + line for line in lines) + "\n" + close + "}"
        path.write_text(text[:start] + block + text[end + 1:])
    if args.check and changed:
        print("out of date: " + ", ".join(changed))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
