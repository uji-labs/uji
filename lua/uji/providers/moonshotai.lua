return {
    id = "moonshotai",
    name = "Moonshot AI",
    wire = "openai-chat",
    base_url = "https://api.moonshot.ai/v1",
    auth_env = { "MOONSHOT_API_KEY" },
    models = {
        { id = "kimi-k2.6", context = 262144, output = 262144, reasoning = true },
        "kimi-k2-0711-preview",
        "kimi-k2-0905-preview",
        "kimi-k2-thinking",
        "kimi-k2-thinking-turbo",
        "kimi-k2-turbo-preview",
        "kimi-k2.5",
        { id = "kimi-k2.7-code", context = 262144, output = 262144, reasoning = true },
        { id = "kimi-k2.7-code-highspeed", context = 262144, output = 262144, reasoning = true },
        { id = "kimi-k3", context = 1048576, output = 131072, reasoning = true },
    },
}
