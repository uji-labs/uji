local common = require("uji.builtin.apis.common")
local stream = require("uji.builtin.apis.stream")

local MAX_TOKENS = "MAX_TOKENS"
local RANK = { minimal = 1, low = 2, medium = 3, high = 4, xhigh = 5, max = 6 }
local LEVELS = {
    ["gemini-3.8-flash"] = { "low", "medium", "high" },
    ["gemini-3.7-flash"] = { "low", "medium", "high" },
    ["gemini-3.6-flash"] = { "minimal", "low", "medium", "high" },
    ["gemini-3.5-flash"] = { "minimal", "low", "medium", "high" },
    ["gemini-3.5-flash-lite"] = { "minimal", "low", "medium", "high" },
    ["gemini-3.1-pro-preview"] = { "low", "medium", "high" },
    ["gemini-3.1-flash-lite-image"] = { "minimal", "high" },
    ["gemini-3-flash-preview"] = { "minimal", "low", "medium", "high" },
    ["gemini-3-pro-preview"] = { "low", "high" },
}

local Gemini = uji.class()

function Gemini:init(opts)
    for key, value in pairs(opts or {}) do
        self[key] = value
    end
end

local function budgeted(model)
    return model:match("^gemini%-2") ~= nil
end

function Gemini:efforts(model)
    if budgeted(model) then
        if model:find("pro", 1, true) then
            return { "low", "medium", "high" }
        end
        return { "off", "low", "medium", "high" }
    end
    return LEVELS[model] or { "low", "high" }
end

function Gemini:level(model, effort)
    local levels = self:efforts(model)
    local wanted = RANK[effort] or 0
    local chosen = levels[1]
    for _, level in ipairs(levels) do
        if RANK[level] <= wanted then
            chosen = level
        end
    end
    return chosen
end

function Gemini:thinking(request)
    local effort = request.effort
    if budgeted(request.model) then
        if effort == "off" then
            return { thinkingBudget = 0 }
        end
        local _, budget = common.fit_thinking(effort, request.max_output)
        return { thinkingBudget = budget > 0 and budget or nil, includeThoughts = true }
    end
    return { thinkingLevel = effort and self:level(request.model, effort) or nil, includeThoughts = true }
end

function Gemini:picture(image)
    return { inlineData = { mimeType = image.media_type, data = image.data } }
end

local function said(text)
    return { text = text }
end

function Gemini:call(tool_call)
    return {
        functionCall = { name = tool_call.name, args = common.arguments(tool_call.arguments) },
        thoughtSignature = tool_call.signature,
    }
end

function Gemini:user(item)
    return {
        role = "user",
        parts = common.parts(item.images, function(image)
            return self:picture(image)
        end, item.text, said),
    }
end

function Gemini:assistant(item)
    local parts = common.map(item.tool_calls, function(tool_call)
        return self:call(tool_call)
    end)
    if item.text ~= "" then
        table.insert(parts, 1, { text = item.text })
    end
    return { role = "model", parts = parts }
end

function Gemini:tool(item)
    return {
        role = "function",
        parts = { { functionResponse = { name = item.name, response = { result = item.content } } } },
    }
end

function Gemini:show(images)
    return {
        {
            role = "user",
            parts = common.parts(images, function(image)
                return self:picture(image)
            end, common.SHOWN, said),
        },
    }
end

function Gemini:spec(tool)
    return {
        functionDeclarations = { { name = tool.name, description = tool.description, parameters = tool.parameters } },
    }
end

function Gemini:body(request)
    local system = common.system(request)
    local shapes = {
        user = function(item)
            return self:user(item, request)
        end,
        assistant = function(item)
            return self:assistant(item, request)
        end,
        tool = function(item)
            return self:tool(item, request)
        end,
    }
    return {
        generationConfig = request.reasoning and { thinkingConfig = self:thinking(request) } or nil,
        systemInstruction = system ~= "" and { parts = { { text = system } } } or nil,
        contents = common.translate(request.messages, shapes, function(images)
            return self:show(images)
        end),
        tools = common.nonempty(common.map(request.tools, function(tool)
            return self:spec(tool)
        end)),
    }
end

function Gemini:read(event, parts)
    local thoughts, text = {}, {}
    for _, candidate in ipairs(event.candidates or {}) do
        for _, part in ipairs(candidate.content and candidate.content.parts or {}) do
            if part.text and part.thought == true then
                thoughts[#thoughts + 1] = part.text
            elseif part.text then
                text[#text + 1] = part.text
            end
        end
    end
    if #thoughts > 0 then
        parts:push_reasoning(table.concat(thoughts))
    end
    if #text > 0 then
        parts:push_text(table.concat(text))
    end
    local reported = event.usageMetadata
    if reported then
        local cached = reported.cachedContentTokenCount or 0
        parts.usage = {
            input = math.max((reported.promptTokenCount or 0) - cached, 0),
            output = (reported.candidatesTokenCount or 0) + (reported.thoughtsTokenCount or 0),
            cache_read = cached,
            cache_write = 0,
        }
    end
    for _, candidate in ipairs(event.candidates or {}) do
        if candidate.finishReason == MAX_TOKENS then
            parts.hit_limit = true
        end
        if candidate.finishReason then
            parts:finish()
        end
    end
    local first = event.candidates and event.candidates[1]
    for index, part in ipairs(first and first.content and first.content.parts or {}) do
        if part.functionCall then
            local entry = parts:call(index - 1)
            entry.name = part.functionCall.name
            entry.id = entry.name
            entry.arguments = uji.json.encode(part.functionCall.args or {})
            entry.signature = part.thoughtSignature
        end
    end
end

function Gemini:stream(request, reply)
    return stream.run({
        url = request.provider.base_url .. "/models/" .. request.model .. ":streamGenerateContent?alt=sse",
        headers = { ["x-goog-api-key"] = request.auth.key },
        body = self:body(request),
        read = function(event, parts)
            self:read(event, parts)
        end,
    }, reply)
end

return Gemini
