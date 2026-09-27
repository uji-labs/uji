return {
    id = "cerebras",
    name = "Cerebras",
    wire = "openai-chat",
    base_url = "https://api.cerebras.ai/v1",
    auth_env = { "CEREBRAS_API_KEY" },
    models = {
        { id = "gpt-oss-120b", context = 131072, output = 40960, reasoning = true },
        "gemma-4-31b",
        { id = "qwen-3.8-27b", context = 65536, output = 32768, reasoning = true },
    },
}
