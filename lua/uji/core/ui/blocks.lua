local class = require("uji.core.class")
local event = require("uji.core.event")
local markdown = require("uji.core.ui.markdown")
local notices = require("uji.core.notices")
local spans = require("uji.core.ui.spans")
local sys = require("uji.sys")
local text = require("uji.core.ui.text")
local tokens = require("uji.core.agent.tokens")
local tool = require("uji.core.tool")
local Window = require("uji.core.ui.window")

local MAX_TOOL_PREVIEW = 8
local ARGUMENT_PREVIEW = 200

local function wrapped(out, value, width, style, prefix, block)
    local trailing = block and 1 or 0
    local inner = math.max(width - text.width(prefix) - trailing, 0)
    for _, chunk in ipairs(text.wrap(value, inner)) do
        if block then
            local pad = string.rep(" ", math.max(inner - text.width(chunk), 0))
            out[#out + 1] = { { prefix .. chunk .. " " .. pad, style } }
        else
            out[#out + 1] = { { prefix .. chunk, style } }
        end
    end
end

local Blocks = class()

Blocks.wrapped = wrapped

function Blocks:init()
    self.labels = {}
end

function Blocks:label(call)
    local cached = self.labels[call.id]
    if cached ~= nil then
        return cached or nil
    end
    local found = self:describe(call)
    self.labels[call.id] = found or false
    return found
end

function Blocks:describe(call)
    local entry = tool.get(call.name)
    if not entry then
        return nil
    end
    local ok, args = pcall(sys.json.decode, call.arguments or "", { nulls = false })
    if not ok or type(args) ~= "table" then
        return nil
    end
    local fine, detail = pcall(tool.detail, entry, args)
    if not fine then
        notices.push(call.name .. " subject: " .. sys.message(detail))
        detail = nil
    end
    local verb = entry.display and entry.display.verb
    if verb and detail then
        return verb .. " " .. detail
    elseif verb then
        return verb .. " " .. call.name
    elseif detail then
        return "Called " .. call.name .. " " .. detail
    end
end

function Blocks:markdown(out, value, width, continuing, events)
    local lines = markdown.render(events or markdown.parse(value), width - 1, self.palette, self.styles, continuing)
    for _, line in ipairs(lines) do
        table.insert(line, 1, { " ", 0 })
        out[#out + 1] = line
    end
end

function Blocks:tool_header(out, call, width)
    local palette = self.palette
    local head = self:label(call)
    if not head then
        local chars = text.chars(call.arguments or "")
        head = "Called " .. call.name .. " " .. table.concat(chars, "", 1, math.min(#chars, ARGUMENT_PREVIEW))
    end
    head = head:gsub("\n", " ")
    local chunks = text.wrap(head, math.max(width - 4, 1))
    out[#out + 1] = { { " • ", palette.muted }, { chunks[1] or "", palette.bold } }
    for index = 2, #chunks do
        out[#out + 1] = { { "   " .. chunks[index], palette.text } }
    end
end

function Blocks:tool_output(out, content, width)
    local palette = self.palette
    local failed = content:sub(1, 6) == "error:" or content:sub(1, 7) == "denied:"
    local style = failed and palette.error or palette.muted
    local available = math.max(width - 5, 1)
    local rows, hidden = {}, 0
    for _, raw in ipairs(text.lines(content)) do
        local shown = text.clip(raw, math.max(MAX_TOOL_PREVIEW - #rows, 0) * available)
        for _, chunk in ipairs(shown == "" and raw ~= "" and {} or text.wrap(shown, available)) do
            rows[#rows + 1] = chunk
        end
        if #shown < #raw then
            hidden = hidden + math.ceil(text.width(raw:sub(#shown + 1)) / available)
        end
    end
    hidden = hidden + math.max(#rows - MAX_TOOL_PREVIEW, 0)
    for index = 1, math.min(#rows, MAX_TOOL_PREVIEW) do
        out[#out + 1] = { { (index == 1 and "   └ " or "     ") .. rows[index], style } }
    end
    if hidden > 0 then
        out[#out + 1] = { { "     … +" .. hidden .. " lines", palette.dim } }
    end
end

function Blocks:divider(out, width)
    local label = " compacted "
    local bar = string.rep("─", math.floor(math.max(width - #label - 2, 0) / 2))
    out[#out + 1] = { { " " .. bar .. label .. bar, self.palette.dim } }
end

function Blocks:message(out, message, width)
    local palette = self.palette
    local kind = message.type
    if kind == "user" then
        local fill = { { string.rep(" ", width), palette.user } }
        out[#out + 1] = fill
        wrapped(out, message.text or "", width, palette.user, " ", true)
        out[#out + 1] = fill
    elseif kind == "assistant" then
        local body = message.text or ""
        if body ~= "" then
            self:markdown(out, body, width, false)
        end
        for _, call in ipairs(message.tool_calls or {}) do
            if body ~= "" then
                out[#out + 1] = {}
            end
            self:tool_header(out, call, width)
        end
    elseif kind == "tool" then
        self:tool_output(out, message.content or "", width)
    elseif kind == "shell" then
        local header = "! " .. message.command
        if message.code ~= 0 then
            header = header .. "  (exit " .. tostring(message.code) .. ")"
        end
        wrapped(out, header, width, palette.accent, " ", false)
        if (message.output or "") ~= "" then
            self:tool_output(out, message.output, width)
        end
    elseif kind == "system" then
        wrapped(out, message.text or "", width, palette.system, " ", false)
    elseif kind == "error" then
        wrapped(out, message.text or "", width, palette.error, " ", false)
    elseif kind == "compaction" then
        self:divider(out, width)
    end
end

function Blocks:builtin(out, block, width)
    local palette = self.palette
    local kind = block.kind
    if kind == "notice" then
        wrapped(out, block.text, width, palette.notice, " ! ", false)
    elseif kind == "message" then
        self:message(out, block.message, width)
    elseif kind == "pending" then
        self:markdown(out, block.text, width, block.continuing, block.events)
    elseif kind == "thinking" then
        wrapped(out, block.text, width, palette.faint, " │ ", false)
    elseif kind == "queued" then
        wrapped(out, block.text, width, palette.dim, " › ", false)
    end
end

local function payload(block)
    if block.kind ~= "message" then
        return { type = block.kind, text = block.text }
    end
    local message = block.message
    local calls = message.type == "assistant" and message.tool_calls or nil
    return {
        type = message.type,
        text = tokens.text(message),
        name = message.type == "tool" and message.name or nil,
        tool_calls = calls and #calls > 0 and calls or nil,
    }
end

function Blocks:custom(out, block, width)
    local value = event.ask("render_message", payload(block))
    if value == nil then
        return false
    end
    local ok, lines = pcall(Window.lines, value)
    if not ok then
        notices.push("render_message: " .. sys.message(lines))
        return false
    end
    spans.lines(lines, width, true, self.styles, out)
    return true
end

function Blocks:render(out, block, width)
    if self.overrides and self:custom(out, block, width) then
        return
    end
    self:builtin(out, block, width)
end

function Blocks:prepare(palette, styles)
    self.palette = palette
    self.styles = styles
    self.overrides = event.has("render_message")
    return self.overrides
end

return Blocks
