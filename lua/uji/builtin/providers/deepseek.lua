local OpenAI = uji.api.openai

local DeepSeek = uji.class(OpenAI)

function DeepSeek:efforts()
    return { "off", "low", "high", "max" }
end

function DeepSeek:thinking(body, request)
    body.thinking = { type = request.effort == "off" and "disabled" or "enabled" }
    if request.effort ~= "off" then
        body.reasoning_effort = request.effort
    end
end

function DeepSeek:assistant(item, request)
    local out = OpenAI.assistant(self, item, request)
    out.reasoning_content = item.reasoning or ""
    return out
end

uji.provider.add({
    id = "deepseek",
    name = "DeepSeek",
    api = DeepSeek(),
    base_url = "https://api.deepseek.com",
    auth_env = { "DEEPSEEK_API_KEY" },
    models = {
        { id = "deepseek-v4-pro", context = 1000000, output = 384000, reasoning = true, images = false },
        { id = "deepseek-flash", context = 1000000, output = 384000, reasoning = true, images = true },
        { id = "deepseek-v4-flash-vision-exp", context = 1000000, output = 384000, reasoning = true, images = true },
        { id = "deepseek-v4-flash", context = 1000000, output = 384000, reasoning = true, images = true },
    },
})
