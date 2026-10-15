local auth = require("uji.core.auth")
local catalog = require("uji.core.catalog")
local list = require("uji.utils.list")
local model = require("uji.core.model")
local sys = require("uji.sys")
local tables = require("uji.core.tables")
local task = require("uji.core.task")

local M = {}

local ANSWER_SHAPE = table.concat({
    "Answer with one JSON object and nothing else:",
    '{"answers":{"<id>":<number>}},',
    "where the number for each id is how likely yes is, from 0 (certainly no) to 1 (certainly yes).",
    "Answer every id you are given.",
}, " ")

local function decides(provider)
    local api = provider and provider.api
    return type(api) == "table" and type(api.decision) == "function"
end

local function probability(answer)
    if type(answer) == "table" then
        answer = answer.noul
    end
    if type(answer) ~= "number" or answer < 0 or answer > 1 then
        return nil
    end
    return answer
end

local function probabilities(answers, questions)
    local out = {}
    for _, id in ipairs(tables.keys(questions)) do
        out[id] = probability(answers[id])
    end
    return out
end

local function question_listing(questions)
    return table.concat(
        list.mapped(tables.keys(questions), function(id)
            return id .. ": " .. questions[id]
        end),
        "\n"
    )
end

local function decoded(text)
    local ok, found = pcall(uji.json.decode, text and text:match("(%b{})") or "")
    if not ok or type(found) ~= "table" then
        return nil, { kind = "provider", message = "the answer was not JSON" }
    end
    return found.answers or found
end

local function over_chat(provider, opts)
    if provider ~= model.current.provider then
        local name = provider.name or provider.id
        return nil, { kind = "provider", message = name .. " is not the provider in use, so it cannot answer a decision" }
    end
    local answer, failure = model.generate({
        system = ANSWER_SHAPE,
        messages = { { type = "user", text = opts.state .. "\n\n" .. question_listing(opts.questions) } },
    })
    if not answer then
        return nil, failure
    end
    return decoded(answer.text)
end

local function no_key(provider)
    local name = provider.name or provider.id
    return { kind = "auth", message = "no key is set for " .. name .. " - set " .. table.concat(provider.auth_env, " or ") }
end

local function native(provider, opts)
    local credentials, missing = auth.resolve(provider)
    if not credentials then
        return nil, missing
    end
    if #provider.auth_env > 0 and not credentials.key and not credentials.oauth then
        return nil, no_key(provider)
    end
    return provider.api:decision({
        model = opts.model or provider:default_model(),
        state = opts.state,
        questions = opts.questions,
        timeout = opts.timeout,
        auth = credentials,
        provider = { id = provider.id, base_url = provider.base_url },
    })
end

function M.decide(opts)
    local provider = model.current.provider
    if opts.provider then
        provider = catalog.get(opts.provider)
        if not provider then
            return nil, { kind = "provider", message = "no provider is registered as " .. tostring(opts.provider) }
        end
    end
    local calibrated = decides(provider)
    local function ask()
        if calibrated then
            return native(provider, opts)
        end
        return over_chat(provider, opts)
    end
    local finished, ok, outcome, failure = task.timeout(opts.timeout, function()
        return pcall(ask)
    end)
    if not finished then
        return nil, { kind = "http", message = "the decision did not arrive in " .. opts.timeout .. " seconds" }
    end
    if not ok then
        return nil, { kind = "provider", message = sys.message(outcome) }
    end
    if not outcome then
        return nil, failure
    end
    return { probabilities = probabilities(outcome, opts.questions), calibrated = calibrated }
end

return M
