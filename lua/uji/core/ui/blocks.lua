local class = require("uji.core.class")
local event = require("uji.core.event")
local markdown = require("uji.core.ui.markdown")
local notices = require("uji.core.notices")
local sys = require("uji.sys")
local tokens = require("uji.core.agent.tokens")
local tool = require("uji.core.tool")

local function failed(content)
    return content:sub(1, 6) == "error:" or content:sub(1, 7) == "denied:"
end

local Blocks = class()

function Blocks:init()
    self.calls = {}
end

function Blocks:describe(call)
    local cached = call.id and self.calls[call.id]
    if cached then
        return cached
    end
    local described = { name = call.name, arguments = call.arguments or "" }
    local entry = tool.get(call.name)
    local ok, args = pcall(sys.json.decode, call.arguments or "", { nulls = false })
    if entry and ok and type(args) == "table" then
        local fine, detail = pcall(tool.detail, entry, args)
        if not fine then
            notices.push(call.name .. " subject: " .. sys.message(detail))
            detail = nil
        end
        described.verb = entry.display and entry.display.verb
        described.detail = detail
    end
    if call.id then
        self.calls[call.id] = described
    end
    return described
end

function Blocks:element(name, data)
    return self.ctx:element(name, data, self.width)
end

function Blocks:limit(name)
    return self.ctx.limits[name]
end

function Blocks:markdown(block)
    local ctx = self.ctx
    local margin = ctx.limits.reply_margin
    local lines = markdown.render(ctx, {
        events = block.events or markdown.parse(block.text),
        width = self.width - margin,
        continuing = block.continuing,
    })
    if margin > 0 then
        local pad = { string.rep(" ", margin), ctx.styles.plain }
        for _, line in ipairs(lines) do
            table.insert(line, 1, pad)
        end
    end
    return lines
end

function Blocks:message(block)
    local message = block.message
    local kind = message.type
    if kind == "user" then
        return self:element("user", { text = message.text or "" })
    elseif kind == "assistant" then
        local text = message.text or ""
        local calls = {}
        for index, call in ipairs(message.tool_calls or {}) do
            calls[index] = self:describe(call)
        end
        local body = text ~= "" and self:markdown({ text = text }) or {}
        return self:element("assistant", { text = text, body = body, calls = calls })
    elseif kind == "tool" then
        local content = message.content or ""
        return self:element("tool_output", {
            content = content,
            failed = failed(content),
            expanded = block.expanded,
            toggle = block.toggle,
        })
    elseif kind == "shell" then
        local output = message.output or ""
        return self:element("shell", {
            command = message.command,
            code = message.code,
            output = output,
            failed = failed(output),
            expanded = block.expanded,
            toggle = block.toggle,
        })
    elseif kind == "system" or kind == "error" then
        return self:element(kind, { text = message.text or "" })
    elseif kind == "compaction" then
        return self:element("compaction", {})
    end
    return {}
end

function Blocks:builtin(block)
    local kind = block.kind
    if kind == "message" then
        return self:message(block)
    elseif kind == "pending" then
        return self:markdown(block)
    end
    return self:element(kind, { text = block.text })
end

local function payload(block, width)
    if block.kind ~= "message" then
        return { type = block.kind, text = block.text, width = width }
    end
    local message = block.message
    local calls = message.type == "assistant" and message.tool_calls or nil
    return {
        type = message.type,
        text = tokens.text(message),
        name = message.type == "tool" and message.name or nil,
        tool_calls = calls and #calls > 0 and calls or nil,
        width = width,
    }
end

local function span(value)
    return type(value) == "string" or (type(value) == "table" and type(value[1]) == "string")
end

local function lines(value)
    if type(value) ~= "table" then
        return false
    end
    for _, line in ipairs(value) do
        if type(line) ~= "table" then
            return false
        end
        for _, part in ipairs(line) do
            if not span(part) then
                return false
            end
        end
    end
    return true
end

function Blocks:custom(block)
    local value = event.ask("render_message", payload(block, self.width))
    if value == nil then
        return nil
    end
    if not lines(value) then
        notices.push("render_message: a handler must return a list of lines, and each line a list of spans")
        return nil
    end
    return value
end

function Blocks:render(block)
    return self.overrides and self:custom(block) or self:builtin(block)
end

function Blocks:prepare(ctx, width)
    self.ctx = ctx
    self.width = width
    self.overrides = event.has("render_message")
    return self.overrides
end

return Blocks
