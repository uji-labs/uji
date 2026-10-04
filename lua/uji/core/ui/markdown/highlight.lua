local class = require("uji.core.class")

local function words(list)
    local set = {}
    for word in list:gmatch("%S+") do
        set[word] = true
    end
    return set
end

local C_COMMENTS = { { "/*", "*/", "comment" } }

local JAVASCRIPT = "async await break case catch class const continue debugger default delete do else export extends false finally "
    .. "for from function if import in instanceof let new null of return static super switch this throw true try typeof undefined "
    .. "var void while with yield"

local C = "auto bool break case char const continue default do double else enum extern false float for goto if inline int long "
    .. "NULL register return short signed sizeof static struct switch true typedef union unsigned void volatile while"

local LANGUAGES = {
    python = {
        comment = "#",
        blocks = { { '"""', '"""', "string" }, { "'''", "'''", "string" } },
        quotes = "\"'",
        keywords = words(
            "and as assert async await break case class continue def del elif else except False finally for from global if "
                .. "import in is lambda match None nonlocal not or pass raise return self True try while with yield"
        ),
    },
    lua = {
        comment = "--",
        blocks = { { "--[[", "]]", "comment" }, { "[[", "]]", "string" } },
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

function Highlighter:opening(line, at)
    for _, block in ipairs(self.language.blocks or {}) do
        if line:sub(at, at + #block[1] - 1) == block[1] then
            return block
        end
    end
end

local function quoted(line, at)
    local quote = line:sub(at, at)
    local index = at + 1
    while index <= #line do
        local char = line:sub(index, index)
        if char == "\\" then
            index = index + 2
        elseif char == quote then
            return index
        else
            index = index + 1
        end
    end
    return #line
end

function Highlighter:line(line)
    local spans = {}
    local function add(piece, kind)
        local style = self.styles[kind]
        local last = spans[#spans]
        if last and last[2] == style then
            last[1] = last[1] .. piece
        else
            spans[#spans + 1] = { piece, style }
        end
    end
    local language = self.language
    local at = 1
    while at <= #line do
        local block = self.block or self:opening(line, at)
        local char = line:sub(at, at)
        if block then
            local from = self.block and at or at + #block[1]
            local stop = line:find(block[2], from, true)
            local finish = stop and stop + #block[2] - 1 or #line
            add(line:sub(at, finish), block[3])
            self.block = not stop and block or nil
            at = finish + 1
        elseif language.comment and line:sub(at, at + #language.comment - 1) == language.comment then
            add(line:sub(at), "comment")
            at = #line + 1
        elseif language.quotes:find(char, 1, true) then
            local finish = quoted(line, at)
            add(line:sub(at, finish), "string")
            at = finish + 1
        elseif char:match("%d") then
            local number = line:match("^%d[%w%.]*", at)
            add(number, "number")
            at = at + #number
        elseif char:match("[%a_]") then
            local word = line:match("^[%w_]+", at)
            add(word, language.keywords[language.lower and word:lower() or word] and "keyword" or "plain")
            at = at + #word
        else
            add(char, "plain")
            at = at + 1
        end
    end
    return spans
end

local M = {}

function M.new(info, palette)
    local name = info and info:match("^[%w_+#-]+")
    name = name and name:lower()
    local language = name and LANGUAGES[ALIASES[name] or name]
    return language and Highlighter(language, palette)
end

return M
