local common = require("uji.builtin.apis.common")
local Responses = uji.api.responses

local OpenAI = uji.class(Responses)

OpenAI.strict = true
OpenAI.oauth_url = "https://chatgpt.com/backend-api/codex/responses"

function OpenAI:url(request)
    return request.auth.oauth and self.oauth_url or Responses.url(self, request)
end

function OpenAI:headers(request)
    local session = request.auth.oauth
    if not session then
        return Responses.headers(self, request)
    end
    return {
        Authorization = common.bearer(session.token),
        ["ChatGPT-Account-Id"] = session.account_id,
        originator = "uji",
        session_id = common.session(request),
    }
end

function OpenAI:body(request)
    local out = Responses.body(self, request)
    if request.auth.oauth then
        out.max_output_tokens = nil
        out.tools = out.tools or uji.json.array({})
        out.tool_choice = "auto"
        out.parallel_tool_calls = true
        if out.input[1] and out.input[1].role == "system" then
            out.input[1].role = "developer"
        end
    end
    return out
end

local FULL = { "off", "minimal", "low", "medium", "high", "xhigh", "max" }
local GPT5 = { "minimal", "low", "medium", "high" }

uji.provider.add({
    id = "openai",
    name = "OpenAI",
    api = OpenAI(),
    base_url = "https://api.openai.com/v1",
    auth_env = { "OPENAI_API_KEY" },
    oauth = {
        client_id = "app_EMoamEEZ73f0CkXaXp7hrann",
        authorize_url = "https://auth.openai.com/oauth/authorize",
        token_url = "https://auth.openai.com/oauth/token",
        scopes = "openid profile email offline_access",
        redirect_port = 1455,
        redirect_path = "/auth/callback",
        token_body = "form",
        account_id_claim = { "https://api.openai.com/auth", "chatgpt_account_id" },
        device = {
            code_url = "https://auth.openai.com/api/accounts/deviceauth/usercode",
            poll_url = "https://auth.openai.com/api/accounts/deviceauth/token",
            verification_url = "https://auth.openai.com/codex/device",
            redirect_uri = "https://auth.openai.com/deviceauth/callback",
        },
    },
    models = {
        { id = "gpt-5.5", context = 1050000, output = 128000, reasoning = true, images = true, efforts = FULL },
        { id = "gpt-4", context = 8192, output = 8192, images = false },
        { id = "gpt-4-turbo", context = 128000, output = 4096, images = true },
        { id = "gpt-4.1", context = 1047576, output = 32768, images = true },
        { id = "gpt-4.1-mini", context = 1047576, output = 32768, images = true },
        { id = "gpt-4.1-nano", context = 1047576, output = 32768, images = true },
        { id = "gpt-4o", context = 128000, output = 16384, images = true },
        { id = "gpt-4o-2024-05-13", context = 128000, output = 4096, images = true },
        { id = "gpt-4o-2024-08-06", context = 128000, output = 16384, images = true },
        { id = "gpt-4o-2024-11-20", context = 128000, output = 16384, images = true },
        { id = "gpt-4o-mini", context = 128000, output = 16384, images = true },
        { id = "gpt-5", context = 400000, output = 128000, reasoning = true, images = true, efforts = GPT5 },
        "gpt-5-chat-latest",
        { id = "gpt-5-mini", context = 400000, output = 128000, reasoning = true, images = true, efforts = GPT5 },
        { id = "gpt-5-nano", context = 400000, output = 128000, reasoning = true, images = true, efforts = GPT5 },
        { id = "gpt-5-pro", context = 400000, output = 272000, reasoning = true, images = true },
        { id = "gpt-5.1", context = 400000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.2", context = 400000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.2-chat-latest", context = 128000, output = 16384, reasoning = true, images = true },
        { id = "gpt-5.2-pro", context = 400000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.3-chat-latest", context = 128000, output = 16384, images = true },
        { id = "gpt-5.3-codex", context = 400000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.3-codex-spark", context = 128000, output = 32000, reasoning = true, images = true },
        { id = "gpt-5.4", context = 1050000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.4-mini", context = 400000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.4-nano", context = 400000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.4-pro", context = 1050000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.5-pro", context = 1050000, output = 128000, reasoning = true, images = true },
        { id = "gpt-5.6-luna", context = 1050000, output = 128000, reasoning = true, images = true, efforts = FULL },
        { id = "gpt-5.6-sol", context = 1050000, output = 128000, reasoning = true, images = true, efforts = FULL },
        { id = "gpt-5.6-terra", context = 1050000, output = 128000, reasoning = true, images = true, efforts = FULL },
        { id = "gpt-6-astra", context = 1050000, output = 128000, reasoning = true, images = true },
        { id = "gpt-realtime-2.1", context = 128000, output = 32000, reasoning = true, images = true },
        { id = "o1", context = 200000, output = 100000, reasoning = true, images = true },
        { id = "o1-pro", context = 200000, output = 100000, reasoning = true, images = true },
        { id = "o3", context = 200000, output = 100000, reasoning = true, images = true },
        { id = "o3-mini", context = 200000, output = 100000, reasoning = true, images = false },
        { id = "o3-pro", context = 200000, output = 100000, reasoning = true, images = true },
        { id = "o4-mini", context = 200000, output = 100000, reasoning = true, images = true },
        { id = "chatgpt-image-latest", images = true },
        { id = "gpt-image-1.5", images = true },
        { id = "text-embedding-ada-002", context = 8192, output = 1536, images = false },
        { id = "gpt-image-1", images = true },
        { id = "gpt-image-1-mini", images = true },
        { id = "gpt-image-2", images = true },
        { id = "gpt-3.5-turbo", context = 16385, output = 4096, images = false },
        { id = "gpt-5.6", context = 1050000, output = 128000, reasoning = true, images = true, efforts = FULL },
        { id = "text-embedding-3-small", context = 8191, output = 1536, images = false },
        { id = "text-embedding-3-large", context = 8191, output = 3072, images = false },
    },
})
