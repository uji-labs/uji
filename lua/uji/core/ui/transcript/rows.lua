local Compaction = require("uji.core.ui.transcript.compaction")
local Custom = require("uji.core.ui.transcript.custom")
local ErrorMessage = require("uji.core.ui.transcript.error")
local ito = require("ito")
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

function M.reply(ctx, blocks)
    local margin = ctx.limits.reply_margin
    local out = {}
    for index, block in ipairs(blocks) do
        out[index] = margin > 0 and ito.HStack({ ito.Text(string.rep(" ", margin)), block }) or block
    end
    return out
end

local BODY = {
    user = function(_, message)
        return { UserMessage({ message = message }) }
    end,
    assistant = function(ctx, message)
        local text = message.text or ""
        local out = text ~= "" and M.reply(ctx, markdown.blocks(ctx, markdown.parse(text))) or {}
        for _, call in ipairs(message.tool_calls or {}) do
            if text ~= "" then
                out[#out + 1] = ito.Spacer():height(1)
            end
            out[#out + 1] = ToolCall({ call = call })
        end
        return out
    end,
    tool = function(_, message, props)
        local content = message.content or ""
        return {
            ToolOutput({ content = content, failed = failed(content), expanded = props.expanded, toggle = props.toggle }),
        }
    end,
    shell = function(_, message, props)
        local output = message.output or ""
        return {
            Shell({
                command = message.command,
                code = message.code,
                output = output,
                failed = failed(output),
                expanded = props.expanded,
                toggle = props.toggle,
            }),
        }
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

function M.entry(ctx, message, props)
    local out = {}
    if props.gap > 0 then
        out[1] = ito.Spacer():height(props.gap)
    end
    if props.thinking and message.reasoning and message.reasoning ~= "" then
        out[#out + 1] = Custom({
            payload = { type = "thinking", text = message.reasoning },
            fallback = Thinking({ text = message.reasoning }),
        })
    end
    local body = BODY[message.type]
    local views = body and body(ctx, message, props) or {}
    if props.custom then
        local listed = message.type == "assistant" and message.tool_calls or nil
        out[#out + 1] = Custom({
            payload = {
                type = message.type,
                text = tokens.text(message),
                name = message.type == "tool" and message.name or nil,
                tool_calls = listed and #listed > 0 and listed or nil,
            },
            fallback = ito.VStack(views),
        })
        return out
    end
    for _, view in ipairs(views) do
        out[#out + 1] = view
    end
    return out
end

return M
