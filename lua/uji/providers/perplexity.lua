return {
    id = "perplexity",
    name = "Perplexity",
    wire = "openai-chat",
    base_url = "https://api.perplexity.ai",
    auth_env = { "PERPLEXITY_API_KEY" },
    models = {
        { id = "sonar", context = 128000, output = 4096 },
        { id = "sonar-pro", context = 200000, output = 8192 },
        { id = "sonar-reasoning-pro", context = 128000, output = 4096, reasoning = true },
        { id = "sonar-deep-research", context = 128000, output = 32768, reasoning = true },
    },
}
