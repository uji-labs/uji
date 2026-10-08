local app = require("uji.core.app")
local event = require("uji.core.event")
local Footer = require("uji.core.ui.transcript.footer")
local host = require("uji.core.ui.host")
local ito = require("ito")
local Jump = require("uji.core.ui.transcript.jump")
local list = require("uji.utils.list")
local Live = require("uji.core.ui.transcript.live")
local Message = require("uji.core.ui.transcript.message")

local LIVE = {}

local function opens_group(message)
    return message.type == "tool" or (message.type == "assistant" and #(message.tool_calls or {}) > 0)
end

local function before(entries, index)
    for at = index - 1, 1, -1 do
        local message = entries[at].message
        if message.type ~= "context" then
            return message
        end
    end
end

local function identity(item)
    return item == LIVE and LIVE or item.id
end

local function answers(entries, index)
    local last = index
    while entries[last + 1] and entries[last + 1].message.type ~= "assistant" and entries[last + 1].message.type ~= "user" do
        last = last + 1
    end
    local span, at = last - index, 0
    return list.mapped(entries[index].message.tool_calls or {}, function(call)
        for step = 1, span do
            local entry = entries[index + 1 + (at + step - 1) % span]
            if entry.message.type == "tool" and entry.message.tool_call_id == call.id then
                at = (at + step) % span
                return entry
            end
        end
        return false
    end)
end

local function claimed(entries, index)
    local id = entries[index].message.tool_call_id
    for at = index - 1, 1, -1 do
        local message = entries[at].message
        if message.type == "assistant" then
            return #list.filtered(message.tool_calls or {}, function(call)
                return call.id == id
            end) > 0
        elseif message.type == "user" then
            return false
        end
    end
    return false
end

return ito.view(function()
    local ui = host.Host.current
    local ctx = ito.theme()
    local live = ito.remember(function()
        return Live()
    end)
    local expanded = ito.state({})
    local entries = app.session and app.session:entries() or {}
    local items = list.appended(entries, LIVE)
    local function row(item, index)
        if item == LIVE then
            return ito.Group(live:items(ui, ctx, before(entries, index) ~= nil))
        end
        local message = item.message
        if message.type == "context" or (message.type == "tool" and claimed(entries, index)) then
            return nil
        end
        local previous = before(entries, index)
        return Message({
            message = message,
            id = item.id,
            answers = message.type == "assistant" and answers(entries, index) or nil,
            gap = previous and not (opens_group(previous) and message.type == "tool") and ctx.limits.message_gap or 0,
            thinking = ui.theme.show_thinking,
            custom = event.has("render_message"),
            open = expanded,
        })
    end
    return ito.VStack({
        ito.LazyVStack(items, row):item_id(identity):state(ui.scroll):footer(Footer()):grow(),
        ito.Spacer():height(ctx.limits.bottom_gap),
    }):overlay(
        ito.SubcomposeLayout(function()
            if ui.scroll.following then
                return nil
            end
            return ito.HStack({
                ito.Spacer(),
                Jump({
                    follow = function()
                        ui.scroll:to_end()
                    end,
                }),
                ito.Spacer(),
            })
        end),
        ito.Alignment.bottom
    )
end)
