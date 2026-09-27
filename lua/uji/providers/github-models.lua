return {
    id = "github-models",
    name = "GitHub Models",
    wire = "openai-chat",
    base_url = "https://models.github.ai/inference",
    auth_env = { "GITHUB_TOKEN" },
    models = {
        "gpt-5",
        { id = "claude-sonnet-4-5", context = 200000 },
        "gemini-2.5-pro",
        "meta-llama/Llama-3.3-70B-Instruct",
    },
}
