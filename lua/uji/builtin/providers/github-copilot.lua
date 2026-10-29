local auth = require("uji.core.auth")
local copilot = require("uji.core.auth.copilot")
local list = require("uji.utils.list")
local tables = require("uji.core.tables")

local function request_headers(request)
    local session = request.auth.oauth
    local headers = copilot.headers(session and session.token)
    headers["Openai-Intent"] = "conversation-edits"
    local last = request.messages[#request.messages]
    headers["X-Initiator"] = last and (last.type == "tool" or last.type == "assistant") and "agent" or "user"
    for _, message in ipairs(request.messages) do
        if message.images and #message.images > 0 then
            headers["Copilot-Vision-Request"] = "true"
            break
        end
    end
    return headers
end

local function client(Api)
    local Client = uji.class(Api)
    function Client:headers(request, body)
        return tables.merged(Api.headers(self, request, body), request_headers(request))
    end
    return Client()
end

local CHAT = client(uji.api.openai)
CHAT.max_tokens_field = "max_completion_tokens"
local RESPONSES = client(uji.api.responses)
local MESSAGES = client(uji.api.anthropic)
local ROUTES = { ["/chat/completions"] = CHAT, ["/responses"] = RESPONSES, ["/v1/messages"] = MESSAGES }

local Copilot = uji.class()

function Copilot:init()
    self.routes = {}
end

function Copilot:stream(request, reply)
    local route = self.routes[request.model] or CHAT
    local session = request.auth.oauth
    local base_url = (session and session.base_url or request.provider.base_url):gsub("/$", "")
    if route == MESSAGES then
        base_url = base_url .. "/v1"
    end
    local provider = tables.with(request.provider, "base_url", base_url)
    return route:stream(tables.with(request, "provider", provider), reply)
end

local function route(entry)
    if entry.supported_endpoints == nil then
        return CHAT
    end
    for _, endpoint in ipairs(entry.supported_endpoints) do
        if ROUTES[endpoint] then
            return ROUTES[endpoint]
        end
    end
end

local function models(provider)
    local credentials, err = auth.resolve(provider)
    if not credentials or not credentials.oauth then
        error(err and err.message or "sign in to GitHub Copilot with /login first", 0)
    end
    local base_url = credentials.oauth.base_url or provider.base_url
    local body = copilot.request(base_url:gsub("/$", "") .. "/models", nil, credentials.oauth.token)
    if type(body.data) ~= "table" then
        error("Copilot models request returned an unexpected body", 0)
    end
    local out = {}
    for _, entry in ipairs(body.data) do
        local capabilities = entry.capabilities or {}
        local supports = capabilities.supports or {}
        local limits = capabilities.limits or {}
        local api = route(entry)
        if type(entry.id) == "string" and capabilities.type == "chat" and supports.tool_calls and api then
            provider.api.routes[entry.id] = api
            local efforts = list.mapped(supports.reasoning_effort or {}, function(effort)
                return effort == "none" and "off" or effort
            end)
            out[#out + 1] = {
                id = entry.id,
                context = limits.max_context_window_tokens,
                output = limits.max_output_tokens,
                images = supports.vision == true,
                reasoning = #efforts > 0,
                efforts = #efforts > 0 and efforts or nil,
            }
        end
    end
    if #out == 0 then
        error("Copilot returned no chat models with tool support", 0)
    end
    return out
end

uji.provider.add({
    id = "github-copilot",
    name = "GitHub Copilot",
    api = Copilot(),
    base_url = "https://api.githubcopilot.com",
    oauth = {
        client_id = "Iv1.b507a08c87ecfe98",
        token_url = "https://api.github.com/copilot_internal/v2/token",
        api_key = false,
        refresh = copilot.refresh,
        device = {
            code_url = "https://github.com/login/device/code",
            poll_url = "https://github.com/login/oauth/access_token",
            start = copilot.start,
            login = copilot.login,
        },
    },
    models = models,
})
