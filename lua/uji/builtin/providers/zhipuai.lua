local OpenAI = uji.api.openai

local Zai = uji.class(OpenAI)

function Zai:efforts()
    return { "off", "high" }
end

function Zai:thinking(body, request)
    body.thinking = { type = request.effort == "off" and "disabled" or "enabled" }
end

uji.provider.add({
    id = "zhipuai",
    name = "Zhipu AI",
    api = Zai(),
    base_url = "https://open.bigmodel.cn/api/paas/v4",
    auth_env = { "ZHIPU_API_KEY" },
    models = {
        { id = "glm-5.3", context = 1000000, output = 131072, reasoning = true, images = false },
        { id = "glm-4.7", context = 204800, output = 131072, reasoning = true, images = false },
        "glm-5-turbo",
        { id = "glm-5.2", context = 1000000, output = 131072, reasoning = true, images = false },
        "glm-5.2-highspeed",
        { id = "glm-5.3-flash", context = 1000000, output = 131072, reasoning = true, images = true },
        "glm-5.3-highspeed",
        { id = "glm-5", context = 204800, output = 131072, reasoning = true, images = false },
        { id = "glm-5.1", context = 200000, output = 131072, reasoning = true, images = false },
        { id = "glm-5v-turbo", context = 200000, output = 131072, reasoning = true, images = true },
        { id = "glm-4.7-flash", context = 200000, output = 131072, reasoning = true, images = false },
        { id = "glm-4.7-flashx", context = 200000, output = 131072, reasoning = true, images = false },
        { id = "glm-4.5v", context = 64000, output = 16384, reasoning = true, images = true },
        { id = "glm-4.5", context = 131072, output = 98304, reasoning = true, images = false },
        { id = "glm-4.5-flash", context = 131072, output = 98304, reasoning = true, images = false },
        { id = "glm-4.6v", context = 128000, output = 32768, reasoning = true, images = true },
        { id = "glm-4.6", context = 204800, output = 131072, reasoning = true, images = false },
        { id = "glm-4.5-air", context = 131072, output = 98304, reasoning = true, images = false },
    },
})
