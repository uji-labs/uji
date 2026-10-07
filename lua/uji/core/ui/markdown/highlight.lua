local class = require("uji.core.class")
local sys = require("uji.sys")

local LANGUAGE_NAME = "^[%w_+#-]+"

local Highlighter = class()

function Highlighter:init(parser, styles)
    self.parser = parser
    self.styles = styles
end

function Highlighter:line(line)
    local spans = {}
    for index, token in ipairs(self.parser:line(line)) do
        spans[index] = { token.text, token.kind == "plain" and self.styles.text or self.styles.syntax[token.kind] }
    end
    return spans
end

local M = {}

function M.new(info, styles)
    local name = info and info:match(LANGUAGE_NAME)
    local parser = name and sys.highlight(name)
    return parser and Highlighter(parser, styles)
end

return M
