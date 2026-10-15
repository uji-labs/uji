local catalog = require("uji.core.catalog")
local check = require("uji.core.check")
local decision = require("uji.core.decision")
local list = require("uji.utils.list")
local model = require("uji.core.model")

local KNOWN = {}
for _, name in ipairs(model.EFFORTS) do
    KNOWN[name] = true
end

local STATE_KINDS = "a string, or a list of strings to join as paragraphs"

local function state_text(value)
    if type(value) == "string" then
        return value
    end
    local parts = type(value) == "table" and list.filtered(value, function(part)
        return type(part) == "string"
    end)
    if not parts or #parts ~= #value then
        error("uji.model.decide needs state: " .. STATE_KINDS, 3)
    end
    return table.concat(parts, "\n\n")
end

local function questions_asked(value)
    if type(value) ~= "table" then
        error("uji.model.decide needs questions, instructions by id", 3)
    end
    local out = {}
    for id, instructions in pairs(value) do
        if type(id) ~= "string" then
            error("uji.model.decide names each question with a string, not " .. type(id), 3)
        end
        if type(instructions) ~= "string" then
            error("uji.model.decide needs the question " .. id .. " as a string, not " .. type(instructions), 3)
        end
        out[id] = instructions
    end
    return out
end

local function decide(opts)
    check.options(opts, "uji.model.decide")
    return decision.decide({
        provider = opts.provider,
        model = opts.model,
        timeout = opts.timeout,
        state = state_text(opts.state),
        questions = questions_asked(opts.questions),
    })
end

local function use(opts)
    check.options(opts, "uji.model.use")
    if opts.effort ~= nil and not KNOWN[opts.effort] then
        error("effort must be one of " .. table.concat(model.EFFORTS, ", "), 2)
    end
    if opts.provider ~= nil and not catalog.get(opts.provider) then
        error("no provider is registered as " .. tostring(opts.provider), 2)
    end
    local current = model.setting("llm.provider") or ""
    local id = opts.provider or current
    local switched = id ~= current
    if switched then
        model.set_setting("llm.provider", id)
    end
    if opts.base_url ~= nil or switched then
        model.set_setting("llm.base_url", opts.base_url or "")
    end
    if opts.model ~= nil or switched then
        model.remember(id, opts.model or model.model_for(catalog.get(id)))
    end
    if opts.effort ~= nil then
        model.set_setting("llm.effort", opts.effort)
    end
    model.resolve()
end

uji.model = {
    current = function()
        local current = model.current
        return {
            provider = current.id,
            name = current.name,
            model = current.model,
            base_url = current.base_url,
            effort = current.effort,
            images = model.images(),
        }
    end,
    use = use,
    decide = decide,
    efforts = function()
        return { unpack(model.current.efforts) }
    end,
}
