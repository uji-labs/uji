local class = require("uji.core.class")

local NUMBER = "^%d[%w%.]*"
local WORD = "^[%a_][%w_]*"
local PLAIN = "^[^%%w_%s]+"
local STRING_STOP = "[\\%s]"
local ESCAPE_WIDTH = #"\\x"
local LANGUAGE_NAME = "^[%w_+#-]+"
local PATTERN_MAGIC = "%p"
local ESCAPED_MAGIC = "%%%0"

local function words(list)
    local set = {}
    for word in list:gmatch("%S+") do
        set[word] = true
    end
    return set
end

local C_COMMENTS = { { open = "/*", close = "*/", kind = "comment" } }

local JAVASCRIPT = "async await break case catch class const continue debugger default delete do else export extends false finally "
    .. "for from function if import in instanceof let new null of return static super switch this throw true try typeof undefined "
    .. "var void while with yield"

local C = "auto bool break case char const continue default do double else enum extern false float for goto if inline int long "
    .. "NULL register return short signed sizeof static struct switch true typedef union unsigned void volatile while"

local LANGUAGES = {
    python = {
        comment = "#",
        blocks = {
            { open = '"""', close = '"""', kind = "string" },
            { open = "'''", close = "'''", kind = "string" },
        },
        quotes = "\"'",
        keywords = words(
            "and as assert async await break case class continue def del elif else except False finally for from global if "
                .. "import in is lambda match None nonlocal not or pass raise return self True try while with yield"
        ),
    },
    lua = {
        comment = "--",
        blocks = {
            { open = "--[[", close = "]]", kind = "comment" },
            { open = "[[", close = "]]", kind = "string" },
        },
        quotes = "\"'",
        keywords = words(
            "and break do else elseif end false for function goto if in local nil not or repeat return self then true until while"
        ),
    },
    rust = {
        comment = "//",
        blocks = C_COMMENTS,
        quotes = '"',
        keywords = words(
            "as async await break const continue crate dyn else enum Err extern false fn for if impl in let loop match mod move mut "
                .. "None Ok pub ref return self Self Some static struct super trait true type unsafe use where while"
        ),
    },
    javascript = { comment = "//", blocks = C_COMMENTS, quotes = "\"'`", keywords = words(JAVASCRIPT) },
    typescript = {
        comment = "//",
        blocks = C_COMMENTS,
        quotes = "\"'`",
        keywords = words(
            JAVASCRIPT
                .. " abstract any as boolean declare enum implements interface keyof namespace never number private protected "
                .. "public readonly string type unknown"
        ),
    },
    go = {
        comment = "//",
        blocks = C_COMMENTS,
        quotes = "\"'`",
        keywords = words(
            "break case chan const continue default defer else fallthrough false for func go goto if import interface map nil "
                .. "package range return select struct switch true type var"
        ),
    },
    c = { comment = "//", blocks = C_COMMENTS, quotes = "\"'", keywords = words(C) },
    cpp = {
        comment = "//",
        blocks = C_COMMENTS,
        quotes = "\"'",
        keywords = words(
            C
                .. " catch class constexpr delete explicit friend namespace new noexcept nullptr operator override private "
                .. "protected public template this throw try typename using virtual"
        ),
    },
    java = {
        comment = "//",
        blocks = C_COMMENTS,
        quotes = "\"'",
        keywords = words(
            "abstract boolean break byte case catch char class continue default do double else enum extends false final finally "
                .. "float for if implements import instanceof int interface long new null package private protected public record "
                .. "return short static super switch this throw throws true try var void while"
        ),
    },
    ruby = {
        comment = "#",
        quotes = "\"'",
        keywords = words(
            "alias and begin break case class def do else elsif end ensure false for if in module next nil not or redo rescue "
                .. "retry return self super then true undef unless until when while yield"
        ),
    },
    bash = {
        comment = "#",
        quotes = "\"'",
        keywords = words(
            "case do done echo elif else esac exit export fi for function if in local return set source then unset until while"
        ),
    },
    sql = {
        comment = "--",
        blocks = C_COMMENTS,
        quotes = "'",
        lower = true,
        keywords = words(
            "add all alter and as asc begin between by case commit create delete desc distinct drop else end exists foreign from "
                .. "group having in index inner insert into is join key left like limit not null offset on or order outer primary "
                .. "references right rollback select set table then union update values when where"
        ),
    },
    json = { quotes = '"', keywords = words("true false null") },
    yaml = { comment = "#", quotes = "\"'", keywords = words("true false null yes no") },
    toml = { comment = "#", quotes = "\"'", keywords = words("true false") },
}

local ALIASES = {
    py = "python",
    python3 = "python",
    rs = "rust",
    js = "javascript",
    jsx = "javascript",
    mjs = "javascript",
    ts = "typescript",
    tsx = "typescript",
    golang = "go",
    h = "c",
    ["c++"] = "cpp",
    cc = "cpp",
    cxx = "cpp",
    hpp = "cpp",
    rb = "ruby",
    sh = "bash",
    shell = "bash",
    zsh = "bash",
    yml = "yaml",
    jsonc = "json",
    postgres = "sql",
    postgresql = "sql",
    mysql = "sql",
    sqlite = "sql",
}

local NONE = {}

local function starters(pattern)
    return setmetatable({}, {
        __index = function(set, byte)
            local starts = string.char(byte):find(pattern) ~= nil
            rawset(set, byte, starts)
            return starts
        end,
    })
end

local STARTS_NUMBER = starters(NUMBER)
local STARTS_WORD = starters(WORD)

local function escaped(text)
    return (text:gsub(PATTERN_MAGIC, ESCAPED_MAGIC))
end

for _, language in pairs(LANGUAGES) do
    local starts, opens, stops = {}, {}, {}
    for _, block in ipairs(language.blocks or NONE) do
        local first = block.open:sub(1, 1)
        opens[first:byte()] = opens[first:byte()] or {}
        table.insert(opens[first:byte()], block)
        starts[#starts + 1] = first
    end
    for quote in language.quotes:gmatch(".") do
        stops[quote:byte()] = STRING_STOP:format(escaped(quote))
        starts[#starts + 1] = quote
    end
    if language.comment then
        starts[#starts + 1] = language.comment:sub(1, 1)
    end
    language.opens = opens
    language.stops = stops
    language.plain = PLAIN:format(escaped(table.concat(starts)))
end

local function quoted(line, at, stops)
    local quote = line:byte(at)
    local index = at + 1
    while true do
        local found = line:find(stops, index)
        if not found then
            return #line
        end
        if line:byte(found) == quote then
            return found
        end
        index = found + ESCAPE_WIDTH
    end
end

local Highlighter = class()

function Highlighter:init(language, palette)
    self.language = language
    self.styles = {
        plain = palette.text,
        keyword = palette.highlight,
        string = palette.code,
        number = palette.code,
        comment = palette.faint,
    }
    self.block = nil
end

function Highlighter:inside(block, line, from)
    local stop = line:find(block.close, from, true)
    self.block = not stop and block or nil
    return stop and stop + #block.close - 1 or #line, block.kind
end

function Highlighter:token(line, at)
    local language = self.language
    if self.block then
        return self:inside(self.block, line, at)
    end
    local byte = line:byte(at)
    for _, block in ipairs(language.opens[byte] or NONE) do
        if line:sub(at, at + #block.open - 1) == block.open then
            return self:inside(block, line, at + #block.open)
        end
    end
    local comment = language.comment
    if comment and comment:byte() == byte and line:sub(at, at + #comment - 1) == comment then
        return #line, "comment"
    end
    local stops = language.stops[byte]
    if stops then
        return quoted(line, at, stops), "string"
    end
    if STARTS_NUMBER[byte] then
        local _, finish = line:find(NUMBER, at)
        return finish, "number"
    end
    if STARTS_WORD[byte] then
        local _, finish = line:find(WORD, at)
        local word = line:sub(at, finish)
        return finish, language.keywords[language.lower and word:lower() or word] and "keyword" or "plain"
    end
    local _, finish = line:find(language.plain, at)
    return finish or at, "plain"
end

function Highlighter:line(line)
    local spans = {}
    local from, style = 1, nil
    local at = 1
    while at <= #line do
        local finish, kind = self:token(line, at)
        local current = self.styles[kind]
        if current ~= style then
            if at > from then
                spans[#spans + 1] = { line:sub(from, at - 1), style }
            end
            from, style = at, current
        end
        at = finish + 1
    end
    if from <= #line then
        spans[#spans + 1] = { line:sub(from), style }
    end
    return spans
end

local M = {}

function M.new(info, palette)
    local name = info and info:match(LANGUAGE_NAME)
    name = name and name:lower()
    local language = name and LANGUAGES[ALIASES[name] or name]
    return language and Highlighter(language, palette)
end

return M
