local ito = require("ito")
local list = require("uji.utils.list")
local sys = require("uji.sys")
local task = require("uji.core.task")

local LANGUAGE_NAME = "^[%w_+#-]+"

local M = {}

function M.tokens(info, lines)
    local language = info and info:match(LANGUAGE_NAME)
    local text = table.concat(lines, "\n")
    local found = ito.state({ lines = {}, tokens = {} })
    local job = ito.remember(function()
        return {}
    end)
    ito.remember(function()
        if job.running then
            job.running:cancel()
        end
        local asked = list.extended({}, lines)
        job.running = language
            and task.spawn(function()
                local tokens = sys.highlight(language, text)
                job.running = nil
                if tokens then
                    found.value = { lines = asked, tokens = tokens }
                end
            end)
    end, language, text)
    local done = found.value
    return list.mapped(lines, function(line, index)
        return done.lines[index] == line and done.tokens[index] or false
    end)
end

function M.spans(tokens, styles)
    return list.mapped(tokens, function(token)
        return { token.text, token.kind == "plain" and styles.text or styles.syntax[token.kind] }
    end)
end

return M
