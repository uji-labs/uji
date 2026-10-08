local sys = require("uji.sys")
local tables = require("uji.core.tables")

local EDGE = 1568
local LIMIT = 5 * 1024 * 1024
local RAW_LIMIT = math.floor(LIMIT * 3 / 4)
local KEEP = 20
local BUDGET = 16 * 1024 * 1024
local PIXELS_PER_TOKEN = 750
local EXTENSIONS = { png = true, jpg = true, jpeg = true, gif = true, webp = true }
local MEDIA = { ["image/png"] = true, ["image/jpeg"] = true, ["image/gif"] = true, ["image/webp"] = true }
local REFUSED = { [400] = true, [413] = true, [415] = true, [422] = true }
local TEXT_ONLY = "this model does not take images"
local OVER_BUDGET = "only the newest images fit in a request"

local M = { EDGE = EDGE, LIMIT = LIMIT }

local function words(value)
    local out, word, quote, escaped = {}, nil, nil, false
    for char in value:gmatch(".") do
        if escaped then
            word, escaped = (word or "") .. char, false
        elseif char == "\\" and quote ~= "'" then
            escaped = true
        elseif quote then
            if char == quote then
                quote = nil
            else
                word = word .. char
            end
        elseif char == "'" or char == '"' then
            quote, word = char, word or ""
        elseif char:match("%s") then
            out[#out + 1], word = word, nil
        else
            word = (word or "") .. char
        end
    end
    out[#out + 1] = word
    return out
end

local function unlink(word)
    local file = word:match("^file://(.*)$")
    if not file then
        return word
    end
    return (file:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function attachment(name, image, err)
    if not image then
        return nil, name .. ": " .. tostring(err)
    end
    if #image.data > LIMIT then
        return nil, name .. " is larger than 5 MB"
    end
    image.name = name
    return image
end

function M.load(data, name)
    return attachment(name, sys.image.fit(data, EDGE, RAW_LIMIT))
end

function M.named(file)
    local extension = file:match("%.(%w+)$")
    return extension ~= nil and EXTENSIONS[extension:lower()] == true
end

function M.file(file, directory)
    local full = sys.fs.resolve(directory or sys.os.cwd(), file)
    local data, err = sys.fs.read(full)
    if not data then
        return nil, err
    end
    return M.load(data, sys.fs.name(full))
end

function M.clipboard()
    return attachment("clipboard", sys.clipboard.image(EDGE, RAW_LIMIT))
end

function M.paths(value)
    local found = {}
    for _, word in ipairs(words(value)) do
        local file = unlink(word)
        if not M.named(file) then
            return nil
        end
        found[#found + 1] = file
    end
    return #found > 0 and found or nil
end

function M.mentioned(value, directory)
    local found = {}
    for file in value:gmatch("@(%S+)") do
        local image = M.named(file) and M.file(file, directory)
        if image then
            found[#found + 1] = image
        end
    end
    return found
end

local function usable(image)
    if type(image) ~= "table" or not MEDIA[image.media_type] then
        return false
    end
    return type(image.data) == "string" and image.data ~= "" and #image.data <= LIMIT
end

function M.checked(list)
    if list == nil then
        return nil
    end
    if type(list) ~= "table" then
        return nil, "images must be a list, not a " .. type(list)
    end
    local kept, dropped = {}, 0
    for _, image in ipairs(list) do
        if usable(image) then
            kept[#kept + 1] = image
        else
            dropped = dropped + 1
        end
    end
    local problem = dropped > 0 and string.format("%d image(s) had no media_type, no data or more than 5 MB", dropped)
    return #kept > 0 and kept or nil, problem or nil
end

local function note(message, dropped, reason)
    local line = string.format("[%d image(s) left out: %s]", dropped, reason)
    local copy = tables.copy(message)
    if message.type == "tool" then
        copy.content = (message.content or "") .. "\n" .. line
    else
        copy.text = (message.text or "") .. "\n\n" .. line
    end
    return copy
end

function M.prepare(messages, accepts)
    local out, kept, bytes = {}, 0, 0
    for index = #messages, 1, -1 do
        local message = messages[index]
        if message.images then
            local keep, dropped = {}, 0
            for at = #message.images, 1, -1 do
                local image = message.images[at]
                if accepts ~= false and kept < KEEP and bytes + #image.data <= BUDGET then
                    table.insert(keep, 1, image)
                    kept, bytes = kept + 1, bytes + #image.data
                else
                    dropped = dropped + 1
                end
            end
            if dropped > 0 then
                message = note(message, dropped, accepts == false and TEXT_ONLY or OVER_BUDGET)
                message.images = #keep > 0 and keep or nil
            end
        end
        out[index] = message
    end
    return out
end

function M.present(messages)
    for _, message in ipairs(messages) do
        if message.images then
            return true
        end
    end
    return false
end

function M.refused(failure)
    return type(failure) == "table" and failure.kind == "http" and REFUSED[failure.status] == true
end

function M.tokens(image)
    return math.ceil((image.width or EDGE) * (image.height or EDGE) / PIXELS_PER_TOKEN)
end

return M
