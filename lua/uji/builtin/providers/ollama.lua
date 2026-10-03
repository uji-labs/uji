uji.provider.add({
    id = "ollama",
    name = "Ollama",
    api = uji.api.openai(),
    base_url = "http://localhost:11434/v1",
    auth_env = {},
    models = { "llama3.2", "llama3.1", "qwen3", "mistral" },
})
