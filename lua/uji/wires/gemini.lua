local common = require("uji.wires.common")
local stream = require("uji.wires.stream")

local MAX_TOKENS = "MAX_TOKENS"

local function call(tool_call)
    return { functionCall = { name = tool_call.name, args = common.arguments(tool_call.arguments) } }
end

local SHAPES = {
    user = function(item)
        return { role = "user", parts = { { text = item.text } } }
    end,
    assistant = function(item)
        local parts = common.map(item.tool_calls, call)
        if item.text ~= "" then
            table.insert(parts, 1, { text = item.text })
        end
        return { role = "model", parts = parts }
    end,
    tool = function(item)
        return {
            role = "function",
            parts = { { functionResponse = { name = item.name, response = { result = item.content } } } },
        }
    end,
}

local function tool(spec)
    return {
        functionDeclarations = { { name = spec.name, description = spec.description, parameters = spec.parameters } },
    }
end

local function body(request)
    local system = common.system(request)
    local _, budget = common.fit_thinking(request.effort, request.max_output)
    return {
        generationConfig = budget > 0 and { thinkingConfig = { thinkingBudget = budget, includeThoughts = true } }
            or nil,
        systemInstruction = system ~= "" and { parts = { { text = system } } } or nil,
        contents = common.translate(request.messages, SHAPES),
        tools = common.nonempty(common.map(request.tools, tool)),
    }
end

local function read(event, parts)
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
        end
    end
end

return {
    stream = function(request, reply)
        local key = request.auth.key
        return stream.run({
            url = request.provider.base_url .. "/models/" .. request.model .. ":streamGenerateContent?alt=sse",
            headers = { ["x-goog-api-key"] = key },
            body = body(request),
            read = read,
        }, reply)
    end,
}
