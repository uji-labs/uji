return {
    id = "deepseek",
    name = "DeepSeek",
    wire = "openai-chat",
    base_url = "https://api.deepseek.com",
    auth_env = { "DEEPSEEK_API_KEY" },
    models = {
        { id = "deepseek-v4-pro", context = 1000000, output = 384000, reasoning = true },
        { id = "deepseek-flash", context = 1000000, output = 384000, reasoning = true },
        { id = "deepseek-v4-flash-vision-exp", context = 1000000, output = 384000, reasoning = true },
        { id = "deepseek-v4-flash", context = 1000000, output = 384000, reasoning = true },
    },
}
