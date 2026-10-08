local catalog = require("uji.core.catalog")
local common = require("uji.builtin.apis.common")
local list = require("uji.utils.list")

local METADATA = "https://models.dev/api.json"
local AGENT = "uji/" .. require("uji.version")

local EFFORTS = { none = "off" }
for _, effort in ipairs(catalog.EFFORTS) do
    EFFORTS[effort] = effort
end

local function client(Api)
    local Client = uji.class(Api)
    function Client:headers(request, ...)
        local out = Api.headers(self, request, ...)
        out["User-Agent"] = AGENT
        out["x-opencode-client"] = "uji"
        out["x-opencode-session"] = common.session(request)
        return out
    end
    return Client
end

local Chat = client(uji.api.openai)

function Chat:assistant(item, request)
    local out = uji.api.openai.assistant(self, item, request)
    if item.reasoning and item.reasoning ~= "" then
        out.reasoning_content = item.reasoning
    end
    return out
end

local CHAT = Chat()
local CLIENTS = {
    ["@ai-sdk/openai"] = client(uji.api.responses)(),
    ["@ai-sdk/anthropic"] = client(uji.api.anthropic)(),
    ["@ai-sdk/google"] = client(uji.api.gemini)(),
}

local function fetch(url)
    local response, err = uji.http.request({ url = url, headers = { ["User-Agent"] = AGENT }, timeout = 10 })
    if not response then
        error(err, 0)
    end
    if response.status ~= 200 then
        error(url .. " answered " .. response.status, 0)
    end
    return uji.json.decode(response.body, { nulls = false })
end

local known = {}

local function metadata(source)
    if not known[source] then
        local all = fetch(METADATA)
        for _, name in ipairs({ "opencode", "opencode-go" }) do
            known[name] = all[name] and all[name].models or {}
        end
    end
    return known[source]
end

local function efforts(options)
    for _, option in ipairs(options or {}) do
        if option.type == "effort" then
            local listed = list.filtered(option.values, function(value)
                return EFFORTS[value] ~= nil
            end)
            local out = list.mapped(listed, function(value)
                return EFFORTS[value]
            end)
            return #out > 0 and out or nil
        end
    end
end

local function images(info)
    if not info.modalities then
        return nil
    end
    for _, kind in ipairs(info.modalities.input or {}) do
        if kind == "image" then
            return true
        end
    end
    return false
end

local function model(id, info)
    if not info then
        return { id = id }
    end
    local limit = info.limit or {}
    return {
        id = id,
        context = limit.context,
        output = limit.output,
        reasoning = info.reasoning == true,
        images = images(info),
        cache = info.cost ~= nil and info.cost.cache_read ~= nil,
        efforts = efforts(info.reasoning_options),
    }
end

local OpenCode = uji.class()

function OpenCode:init(spec)
    self.spec = spec
    self.routes = {}
end

function OpenCode:route(id)
    return self.routes[id] or CHAT
end

function OpenCode:efforts(id)
    local api = self:route(id)
    return api.efforts and api:efforts(id) or catalog.DEFAULT_EFFORTS
end

function OpenCode:stream(request, reply)
    return self:route(request.model):stream(request, reply)
end

function OpenCode:models()
    local info = metadata(self.spec.source)
    local out = {}
    for _, item in ipairs(fetch(self.spec.base_url .. "/models").data) do
        local found = info[item.id]
        self.routes[item.id] = CLIENTS[found and found.provider and found.provider.npm] or CHAT
        out[#out + 1] = model(item.id, found)
    end
    table.sort(out, function(a, b)
        return a.id < b.id
    end)
    return out
end

return function(spec)
    local api = OpenCode(spec)
    uji.provider.add({
        id = spec.id,
        name = spec.name,
        api = api,
        base_url = spec.base_url,
        auth_env = { "OPENCODE_API_KEY" },
        models = function()
            return api:models()
        end,
    })
end
