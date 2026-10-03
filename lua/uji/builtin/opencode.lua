local accepted = {}
for _, effort in ipairs(require("uji.core.catalog").EFFORTS) do
    accepted[effort] = true
end

local function get(url)
    local response, problem = uji.http.request({ url = url, headers = { ["User-Agent"] = "uji" }, timeout = 5 })
    if not response or response.status ~= 200 then
        error("could not fetch OpenCode models from " .. url .. ": " .. tostring(problem or (response and response.status)), 0)
    end
    return uji.json.decode(response.body, { nulls = false })
end

-- OpenCode lists IDs only; models.dev supplies limits and capabilities.
return function(base_url, source, formats)
    local ok, models = pcall(function()
        local inventory = get(base_url .. "/models")
        local metadata = get("https://models.dev/api.json")[source]
        if type(inventory.data) ~= "table" or type(metadata) ~= "table" or type(metadata.models) ~= "table" then
            error("invalid OpenCode model inventory or metadata", 0)
        end
        local found, seen = {}, {}
        for _, entry in ipairs(inventory.data) do
            local id = entry.id
            local info = metadata.models[id]
            local limit = info and info.limit
            if
                formats[id]
                and limit
                and type(limit.context) == "number"
                and limit.context > 0
                and type(limit.output) == "number"
                and limit.output > 0
                and not seen[id]
            then
                local images = false
                for _, modality in ipairs(info.modalities and info.modalities.input or {}) do
                    images = images or modality == "image"
                end
                local efforts
                for _, option in ipairs(type(info.reasoning_options) == "table" and info.reasoning_options or {}) do
                    if type(option) == "table" and option.type == "effort" and type(option.values) == "table" then
                        local supported = {}
                        for _, value in ipairs(option.values) do
                            if accepted[value] then
                                supported[#supported + 1] = value
                            end
                        end
                        efforts = #supported > 0 and supported or nil
                    end
                end
                found[#found + 1] = {
                    id = id,
                    context = limit.context,
                    output = limit.output,
                    reasoning = info.reasoning == true,
                    images = images,
                    cache = info.cost and info.cost.cache_read ~= nil,
                    efforts = efforts,
                }
                seen[id] = true
            end
        end
        table.sort(found, function(a, b)
            return a.id < b.id
        end)
        return found
    end)
    if not ok then
        return {}, tostring(models)
    end
    return models
end
