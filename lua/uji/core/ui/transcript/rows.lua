local Call = require("uji.core.ui.transcript.call")
local Compaction = require("uji.core.ui.transcript.compaction")
local Custom = require("uji.core.ui.transcript.custom")
local ErrorMessage = require("uji.core.ui.transcript.error")
local ito = require("ito")
local list = require("uji.utils.list")
local markdown = require("uji.core.ui.markdown")
local Shell = require("uji.core.ui.transcript.shell")
local SystemMessage = require("uji.core.ui.transcript.system")
local Thinking = require("uji.core.ui.transcript.thinking")
local tokens = require("uji.core.agent.tokens")
local ToolCall = require("uji.core.ui.transcript.tool_call")
local ToolOutput = require("uji.core.ui.transcript.tool_output")
local UserMessage = require("uji.core.ui.transcript.user")

local M = {}

local function failed(content)
    return content:sub(1, 6) == "error:" or content:sub(1, 7) == "denied:"
end

local function payload(message)
    local listed = message.type == "assistant" and message.tool_calls or nil
    return {
        type = message.type,
        text = tokens.text(message),
        name = message.type == "tool" and message.name or nil,
        tool_calls = listed and #listed > 0 and listed or nil,
    }
end

local function shown(message, expanded, toggle)
    local content = message.content or ""
    return ToolOutput({
        content = content,
        summary = message.summary,
        diff = message.diff,
        failed = failed(content),
        expanded = expanded,
        toggle = toggle,
    })
end

local function status(result)
    if not result then
        return "running"
    end
    return failed(result.message.content or "") and "failed" or "done"
end

function M.reply(ctx, blocks)
    local margin = ctx.limits.reply_margin
    return list.mapped(blocks, function(block)
        return margin > 0 and block:padding({ leading = margin }) or block
    end)
end

local BODY = {
    user = function(_, message)
        return { UserMessage({ message = message }) }
    end,
    assistant = function(ctx, message, _, _, results, custom)
        local text = message.text or ""
        local out = text ~= "" and M.reply(ctx, markdown.blocks(ctx, markdown.parse(text))) or {}
        for index, call in ipairs(message.tool_calls or {}) do
            if text ~= "" or index > 1 then
                out[#out + 1] = ito.Spacer():height(1)
            end
            local result = results[index]
            out[#out + 1] = ToolCall({ call = call, status = status(result) })
            if result then
                local view = shown(result.message, result.expanded, result.toggle)
                out[#out + 1] = custom and Custom({ payload = payload(result.message), fallback = view }) or view
            end
        end
        return out
    end,
    tool = function(_, message, expanded, toggle)
        return { shown(message, expanded, toggle) }
    end,
    shell = function(_, message, expanded, toggle)
        local output = message.output or ""
        return {
            Shell({
                command = message.command,
                code = message.code,
                output = output,
                failed = failed(output),
                expanded = expanded,
                toggle = toggle,
            }),
        }
    end,
    job = function(_, message, expanded, toggle)
        local bad = message.state == "timed out" or (message.state ~= "stopped" and (message.code or 0) ~= 0)
        local views = {
            Call({
                label = "Job",
                detail = message.command,
                note = message.status,
                status = bad and "failed" or "done",
            }),
        }
        if message.output and message.output ~= "" then
            views[2] = ToolOutput({
                content = message.output,
                failed = bad,
                expanded = expanded,
                toggle = toggle,
            })
        end
        return views
    end,
    system = function(_, message)
        return { SystemMessage({ text = message.text or "" }) }
    end,
    error = function(_, message)
        return { ErrorMessage({ text = message.text or "" }) }
    end,
    compaction = function()
        return { Compaction() }
    end,
}

function M.entry(ctx, message, gap, thinking, custom, expanded, toggle, results)
    local out = {}
    if gap > 0 then
        out[1] = ito.Spacer():height(gap)
    end
    if thinking and message.reasoning and message.reasoning ~= "" then
        out[#out + 1] = Custom({
            payload = { type = "thinking", text = message.reasoning },
            fallback = Thinking({ text = message.reasoning }),
        })
    end
    local body = BODY[message.type]
    local views = body and body(ctx, message, expanded, toggle, results or {}, custom) or {}
    if custom then
        out[#out + 1] = Custom({ payload = payload(message), fallback = ito.VStack(views) })
        return out
    end
    for _, view in ipairs(views) do
        out[#out + 1] = view
    end
    return out
end

return M
