local class = require("uji.core.class")
local Custom = require("uji.core.ui.transcript.custom")
local event = require("uji.core.event")
local ito = require("ito")
local markdown = require("uji.core.ui.markdown")
local Partial = require("uji.core.ui.transcript.partial")
local rows = require("uji.core.ui.transcript.rows")
local Streamed = require("uji.core.ui.transcript.streamed")
local Thinking = require("uji.core.ui.transcript.thinking")

local function split_committed(pending)
    local at = pending:find("\n[^\n]*$")
    if not at then
        return "", pending
    end
    return pending:sub(1, at), pending:sub(at + 1)
end

local Live = class()

function Live:init()
    self.reasoning = Streamed()
    self.pending = Streamed()
end

function Live:items(ui, ctx, after)
    local thinking = ui.theme.show_thinking
    if self.ctx ~= ctx or self.thinking ~= thinking then
        self.ctx, self.thinking = ctx, thinking
        self.reasoning:clear()
        self.pending:clear()
        self.lead = ito.Spacer():height(ctx.limits.section_gap)
    end
    local custom = event.has("render_message")
    local committed, partial = split_committed(ui.stream:visible())
    self.reasoning:update(thinking and ui.reasoning or "", not custom, function(piece)
        return {
            Custom({ payload = { type = "thinking", text = piece.text }, fallback = Thinking({ text = piece.text }) }),
        }
    end)
    self.pending:update(committed, not custom, function(piece)
        local blocks = rows.reply(ctx, markdown.blocks(ctx, piece.events or markdown.parse(piece.text), piece.continuing))
        if not custom then
            return blocks
        end
        return { Custom({ payload = { type = "pending", text = piece.text }, fallback = ito.VStack(blocks) }) }
    end)
    if self.partial_text ~= partial then
        self.partial_text = partial
        self.partial = partial ~= "" and Partial({ text = partial }) or nil
    end
    local items = {}
    self.reasoning:items(items)
    self.pending:items(items)
    items[#items + 1] = self.partial
    if after and #items > 0 then
        table.insert(items, 1, self.lead)
    end
    return items
end

return Live
