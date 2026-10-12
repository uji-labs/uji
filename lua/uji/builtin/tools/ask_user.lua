local function label(option)
    return type(option) == "table" and option.label or tostring(option)
end

local function described(options)
    for _, option in ipairs(options) do
        if type(option) == "table" and type(option.description) == "string" and option.description ~= "" then
            return true
        end
    end
    return false
end

local function chosen(question, options)
    local choice
    if described(options) then
        choice = uji.ui.pick({
            title = question,
            items = options,
            label = label,
            preview = function(option)
                if type(option) == "table" and option.description then
                    return { option.description }
                end
                return {}
            end,
        })
    else
        choice = uji.ui.select({ title = question, items = options })
    end
    if choice == nil then
        return "the person closed the question without choosing"
    end
    return "the person chose: " .. label(choice)
end

uji.tool.add("ask_user", {
    description = "Ask the person a question and wait for their answer. Use it when a change or a setup needs "
        .. "something only they know, such as which backend, which url, or which of two files. Pass options when the "
        .. "answer is one of a few choices, best first, each with a label and a description of what it means, and leave "
        .. "them out when the person should type the answer.",
    subject = function(args)
        return type(args) == "table" and type(args.question) == "string" and args.question or "a question"
    end,
    policy = "allow",
    parameters = {
        type = "object",
        properties = {
            question = { type = "string", description = "The question to put to the person, short and specific." },
            options = {
                type = "array",
                description = "The answers to choose between, the one you would pick first. Leave it out when the "
                    .. "person types the answer.",
                items = {
                    type = "object",
                    properties = {
                        label = { type = "string", description = "The choice, a few words." },
                        description = { type = "string", description = "What the choice means, so the person can tell them apart." },
                    },
                    required = { "label", "description" },
                    additionalProperties = false,
                },
            },
        },
        required = { "question" },
        additionalProperties = false,
    },
    run = function(args)
        local question = type(args) == "table" and args.question or nil
        if type(question) ~= "string" or question == "" then
            return "error: ask_user needs a question"
        end
        local options = type(args.options) == "table" and args.options or nil
        if options and #options > 0 then
            return chosen(question, options)
        end
        local answer = uji.ui.prompt({ title = question })
        if answer == nil then
            return "the person closed the question without answering"
        end
        return "the person answered: " .. answer
    end,
})
