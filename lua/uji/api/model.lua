local catalog = require("uji.core.catalog")
local check = require("uji.core.check")
local model = require("uji.core.model")

local KNOWN = {}
for _, name in ipairs(model.EFFORTS) do
    KNOWN[name] = true
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
    efforts = function()
        return { unpack(model.current.efforts) }
    end,
}
