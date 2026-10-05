local ito = require("ito")
local Registry = require("uji.core.registry")
local plugin = require("uji.core.plugin")
local sys = require("uji.sys")
local tables = require("uji.core.tables")

local M = {
    events = {},
    counter = 0,
    report = function() end,
}

local function registry(event)
    local found = M.events[event]
    if not found then
        found = plugin.track(Registry(plugin.current))
        M.events = tables.with(M.events, event, found)
    end
    return found
end

local function failed(event, err)
    M.report(event .. " handler error: " .. sys.message(err))
end

function M.on(event, handler, opts)
    local name = opts and opts.name
    if not name then
        M.counter = M.counter + 1
        name = "handler_" .. M.counter
    end
    registry(event):add(name, handler, opts)
    return name
end

function M.off(event, name)
    local found = M.events[event]
    return found ~= nil and found:remove(name)
end

function M.has(event)
    local found = M.events[event]
    return found ~= nil and not found:empty()
end

function M.emit(event, payload)
    local found = M.events[event]
    if not found then
        return
    end
    payload = payload or {}
    payload.event = event
    for _, handler in found:each() do
        local ok, err = pcall(handler, payload)
        if not ok then
            failed(event, err)
        end
    end
end

function M.ask(event, payload)
    local found = M.events[event]
    if not found then
        return nil
    end
    payload.event = event
    for _, handler in found:each() do
        local ok, answer = pcall(handler, payload)
        if not ok then
            failed(event, answer)
        elseif answer ~= nil then
            return answer
        end
    end
end

function M.fold(event, payload, field)
    local found = M.events[event]
    if found then
        payload.event = event
        for _, handler in found:each() do
            local ok, value = pcall(handler, payload)
            if not ok then
                failed(event, value)
            elseif value ~= nil then
                payload[field] = value
            end
        end
    end
    return payload[field]
end

return ito.observable(M)
