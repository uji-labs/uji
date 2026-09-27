local catalog = {}
for _, name in ipairs({
    "openai",
    "anthropic",
    "google",
    "ollama",
    "custom",
    "lmstudio",
    "openrouter",
    "deepseek",
    "xai",
    "groq",
    "mistral",
    "perplexity",
    "together",
    "cerebras",
    "moonshotai",
    "zhipuai",
    "huggingface",
    "fireworks",
    "baseten",
    "nvidia",
    "github-models",
    "opencode-zen",
}) do
    catalog[#catalog + 1] = require("uji.providers." .. name)
end
return catalog
