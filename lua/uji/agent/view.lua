local sys = require("uji.sys")
local tokens = require("uji.agent.tokens")

local SUMMARY_HEADER = "Summary of the earlier part of this conversation:"
local FILES_HEADER = "Files touched so far:"

local M = {}

function M.summary_message(summary, files)
    local text = SUMMARY_HEADER .. "\n\n" .. summary
    if files and #files > 0 then
        text = text .. "\n\n" .. FILES_HEADER .. " " .. table.concat(files, ", ")
    end
    return { type = "user", text = text }
end

function M.previous_summary(message)
    if not message or message.type ~= "user" then
        return nil
    end
    local text = message.text
    if text:sub(1, #SUMMARY_HEADER) ~= SUMMARY_HEADER then
        return nil
    end
    local body = text:sub(#SUMMARY_HEADER + 1)
    local head = body
    local at = 1
    while true do
        local found = body:find(FILES_HEADER, at, true)
        if not found then
            break
        end
        head = body:sub(1, found - 1)
        at = found + 1
    end
    return head:match("^%s*(.-)%s*$")
end

function M.previous_files(message)
    if not message or message.type ~= "user" then
        return {}
    end
    local text = message.text
    local last
    local at = 1
    while true do
        local found = text:find(FILES_HEADER, at, true)
        if not found then
            break
        end
        last = found
        at = found + 1
    end
    if not last then
        return {}
    end
    local listed = text:sub(last + #FILES_HEADER):match("^([^\n]*)") or ""
    local out = {}
    for part in listed:gmatch("[^,]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            out[#out + 1] = trimmed
        end
    end
    return out
end

function M.files_touched(messages)
    local out, seen = {}, {}
    for _, message in ipairs(messages) do
        if message.type == "assistant" then
            for _, call in ipairs(message.tool_calls or {}) do
                local ok, args = pcall(sys.json.decode, call.arguments, { nulls = false })
                local found = ok and type(args) == "table" and args.path
                if type(found) == "string" and not seen[found] then
                    seen[found] = true
                    out[#out + 1] = found
                end
            end
        end
    end
    return out
end

function M.merge_files(into, extra)
    local known = {}
    for _, found in ipairs(into) do
        known[found] = true
    end
    for _, found in ipairs(extra or {}) do
        if not known[found] then
            known[found] = true
            into[#into + 1] = found
        end
    end
    return into
end

function M.build(stored)
    local at = tokens.last_compaction(stored)
    local out = {}
    if at then
        local marker = stored[at].message
        out[1] = M.summary_message(marker.summary, marker.files)
    end
    for index = (at or 0) + 1, #stored do
        local message = stored[index].message
        local kind = message.type
        if kind == "context" then
            out[#out + 1] = { type = "user", text = message.text }
        elseif kind ~= "shell" and kind ~= "compaction" then
            out[#out + 1] = message
        end
    end
    return out
end

local function cut_point(message)
    return message.type ~= "tool"
end

function M.cut_index(messages, keep_recent)
    local points = {}
    for index, message in ipairs(messages) do
        if cut_point(message) then
            points[#points + 1] = index
        end
    end
    if #points == 0 then
        return nil
    end
    local cut = points[1]
    local kept = 0
    for index = #messages, 1, -1 do
        kept = kept + tokens.weigh(messages[index])
        if kept >= keep_recent then
            local found
            for _, point in ipairs(points) do
                if point >= index then
                    found = point
                    break
                end
            end
            cut = found or points[#points]
            break
        end
    end
    if cut > 1 then
        return cut
    end
end

function M.find_cut(stored, keep_recent)
    local marker = tokens.last_compaction(stored)
    local offset = marker or 0
    local messages = {}
    for index = offset + 1, #stored do
        messages[#messages + 1] = stored[index].message
    end
    local first_kept = M.cut_index(messages, keep_recent)
    if not first_kept then
        return nil
    end
    return {
        from = marker or 1,
        through = stored[offset + first_kept - 1].seq,
        compacted = offset + first_kept - 1,
        span = offset + first_kept - (marker or 1),
    }
end

return M
