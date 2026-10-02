local OpenAI = uji.api.openai

local Kimi = uji.class(OpenAI)

function Kimi:efforts()
    return { "off", "high" }
end

function Kimi:thinking(body, request)
    body.thinking = { type = request.effort == "off" and "disabled" or "enabled" }
end

function Kimi:assistant(item, request)
    local out = OpenAI.assistant(self, item, request)
    out.reasoning_content = item.reasoning or ""
    return out
end

uji.provider.add({
    id = "moonshotai",
    name = "Moonshot AI",
    api = Kimi(),
    base_url = "https://api.moonshot.ai/v1",
    auth_env = { "MOONSHOT_API_KEY" },
    models = {
        { id = "kimi-k2.6", context = 262144, output = 262144, reasoning = true, images = true },
        "kimi-k2-0711-preview",
        "kimi-k2-0905-preview",
        "kimi-k2-thinking",
        "kimi-k2-thinking-turbo",
        "kimi-k2-turbo-preview",
        "kimi-k2.5",
        { id = "kimi-k2.7-code", context = 262144, output = 262144, reasoning = true, images = true, efforts = { "high" } },
        { id = "kimi-k2.7-code-highspeed", context = 262144, output = 262144, reasoning = true, images = true, efforts = { "high" } },
        { id = "kimi-k3", context = 1048576, output = 131072, reasoning = true, images = true },
    },
})
