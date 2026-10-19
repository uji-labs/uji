local book = require("uji.docs")
local field = require("uji.builtin.tools.field")

local function page(name)
    local text = book[name]
    if text then
        return text
    end
    return "error: there is no page " .. name .. "; call docs with no page to list every page"
end

uji.tool.add("docs", {
    description = "Read a page of uji's own reference: every `uji.*` function, the config directory, packs, "
        .. "themes, plugins and slash commands, as of the uji that is running. Without `page`, lists every "
        .. "page. Read it only when the person asks you to change how uji itself works, not for the project "
        .. "being worked on.",
    parameters = {
        type = "object",
        properties = {
            page = {
                type = "string",
                description = "The page to read, named as the list names it, such as `api/tool.md`.",
            },
        },
        additionalProperties = false,
    },
    policy = "allow",
    display = { label = "Docs", question = "Read a page of uji's own reference?" },
    run = function(args)
        local name = field.text(args, "page")
        return page(name ~= "" and name or "SUMMARY.md")
    end,
})
