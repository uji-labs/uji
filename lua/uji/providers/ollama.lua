return {
    id = "ollama",
    name = "Ollama",
    wire = "openai-chat",
    base_url = "http://localhost:11434/v1",
    auth_env = {  },
    models = { "llama3.2", "llama3.1", "qwen3", "mistral" },
}
