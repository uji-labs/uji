local class = require("uji.core.class")
local sys = require("uji.sys")
local tables = require("uji.core.tables")

local ACTIONS = { allow = true, ask = true, deny = true }
local STRICTNESS = { allow = 0, ask = 1, deny = 2 }
local PRECEDENCE = { "deny", "allow", "ask" }

local function strictest(left, right)
    if STRICTNESS[right] > STRICTNESS[left] then
        return right
    end
    return left
end

local function matcher(value)
    if #value >= 2 and value:sub(1, 1) == "/" and value:sub(-1) == "/" then
        return sys.regex(value:sub(2, -2))
    end
    if value:find("[%*%?%[]") then
        return sys.glob(value)
    end
    return {
        test = function(_, subject)
            return subject == value
        end,
    }
end

local Policy = class()

function Policy:init()
    self.tools = {}
    self.default = "ask"
end

function Policy.compile(rules, known)
    local policy = Policy()
    local notices = {}
    for _, name in ipairs(tables.keys(rules)) do
        local value = rules[name]
        if name == "default" then
            if type(value) ~= "string" then
                notices[#notices + 1] = "tool policy: default must be allow, ask or deny; asking instead"
            elseif ACTIONS[value] then
                policy.default = value
            else
                notices[#notices + 1] = "tool policy: default `" .. value .. "` is not allow, ask or deny; asking instead"
            end
        elseif not known[name] then
            notices[#notices + 1] = "tool policy: `" .. name .. "` is not a tool, so its rules do nothing"
        else
            policy.tools[name] = Policy.tool_rules(name, value, notices)
        end
    end
    return policy, notices
end

function Policy.tool_rules(name, value, notices)
    if type(value) ~= "table" then
        notices[#notices + 1] = "tool policy: `" .. name .. "` is not a table of rules; asking before every " .. name
        return { rules = {}, default = "ask" }
    end
    local out = { rules = {} }
    if type(value.default) == "string" then
        if ACTIONS[value.default] then
            out.default = value.default
        else
            notices[#notices + 1] = "tool policy: `"
                .. name
                .. "` default `"
                .. value.default
                .. "` is not allow, ask or deny; asking instead"
            out.default = "ask"
        end
    end
    local unreadable = false
    for _, action in ipairs(PRECEDENCE) do
        local entries = value[action]
        if type(entries) == "table" then
            for _, entry in ipairs(entries) do
                local found = type(entry) == "string" and matcher(entry)
                if found then
                    out.rules[#out.rules + 1] = { matcher = found, action = action }
                else
                    unreadable = true
                    notices[#notices + 1] = "tool policy: `"
                        .. name
                        .. "` "
                        .. action
                        .. " rule `"
                        .. tostring(entry)
                        .. "` is not a valid pattern"
                end
            end
        end
    end
    if unreadable then
        local raised = out.default and strictest(out.default, "ask") or "ask"
        if out.default ~= raised then
            notices[#notices + 1] = "tool policy: asking before every " .. name .. ", because part of its policy could not be read"
        end
        out.default = raised
    end
    return out
end

function Policy:match(tool, subject)
    local rules = self.tools[tool]
    if not rules then
        return nil
    end
    for _, rule in ipairs(rules.rules) do
        if rule.matcher:test(subject) then
            return rule.action
        end
    end
end

function Policy:evaluate(tool, subject, declared)
    local rules = self.tools[tool]
    return self:match(tool, subject) or rules and rules.default or declared or self.default
end

function Policy:decide(tool, subject, parts, declared)
    if not parts or #parts == 0 then
        return self:evaluate(tool, subject, declared)
    end
    local action = self:match(tool, subject) or "allow"
    for _, part in ipairs(parts) do
        action = strictest(action, self:evaluate(tool, part, declared))
    end
    return action
end

return Policy
