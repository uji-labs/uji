local list = require("uji.utils.list")

local CHAT = "/v1/chat/completions"

local function usable(entry)
    return entry.available ~= false
        and entry.supports_tools == true
        and list.found(entry.endpoints or {}, function(endpoint)
            return endpoint == CHAT
        end) ~= nil
end

uji.provider.add({
    id = "uberllm",
    name = "UberLLM",
    api = uji.api.openai(),
    base_url = "https://api.uberllm.dev/v1",
    auth_env = { "UBERLLM_API_KEY" },
    models = function(provider)
        local url = provider.base_url .. "/models"
        local response, err = uji.http.request({ url = url, timeout = 10 })
        if not response then
            error(err, 0)
        end
        if response.status ~= 200 then
            error(url .. " answered " .. response.status, 0)
        end
        local entries = uji.json.decode(response.body, { nulls = false }).data or {}
        return list.mapped(list.filtered(entries, usable), function(entry)
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
