uji.provider.add({
    id = "lmstudio",
    name = "LM Studio",
    api = uji.api.openai(),
    base_url = "http://127.0.0.1:1234/v1",
    auth_env = {  },
    models = {
        { id = "qwen/qwen3-coder-30b", context = 262144, output = 65536, images = false },
        { id = "openai/gpt-oss-20b", context = 131072, output = 32768, reasoning = true, images = false },
        { id = "qwen/qwen3-30b-a3b-2507", context = 262144, output = 16384, images = false },
    },
})
