local list = require("uji.utils.list")

local CHAT = "/v1/chat/completions"

local function chat(entry)
    local endpoints = entry.supported_endpoints or { entry.endpoint }
    return entry.model_type == "text" and list.found(endpoints, function(endpoint)
        return endpoint == CHAT
    end) ~= nil
end

uji.provider.add({
    id = "cheaperinference",
    name = "Cheaper Inference",
    api = uji.api.openai(),
    base_url = "https://api.cheaperinference.com/v1",
    auth_env = { "CHEAPER_INFERENCE_API_KEY" },
    models = function(provider)
        local url = provider.base_url:gsub("/v1/?$", "") .. "/public/models"
        local response, err = uji.http.request({ url = url, timeout = 10 })
        if not response then
            error(err, 0)
        end
        if response.status ~= 200 then
            error(url .. " answered " .. response.status, 0)
        end
        local entries = uji.json.decode(response.body, { nulls = false }).models or {}
        return list.mapped(list.filtered(entries, chat), function(entry)
            return {
                id = entry.id,
                context = entry.context_length,
                output = entry.max_output_tokens,
                reasoning = entry.supports_reasoning == true,
                images = entry.supports_vision == true,
            }
        end)
    end,
})
