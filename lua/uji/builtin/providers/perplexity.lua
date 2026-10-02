uji.provider.add({
    id = "perplexity",
    name = "Perplexity",
    api = uji.api.openai(),
    base_url = "https://api.perplexity.ai",
    auth_env = { "PERPLEXITY_API_KEY" },
    models = {
        { id = "sonar", context = 128000, output = 4096, images = false },
        { id = "sonar-pro", context = 200000, output = 8192, images = true },
        { id = "sonar-reasoning-pro", context = 128000, output = 4096, reasoning = true, images = true },
        { id = "sonar-deep-research", context = 128000, output = 32768, reasoning = true, images = false },
    },
})
