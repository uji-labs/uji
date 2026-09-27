local field = require("uji.tools.field")

local MAX_LINES = 2000
local MAX_BYTES = 50 * 1024
local MAX_LINE = 2000
local TRUNCATED = " …[line truncated]"

local function page(path, offset, read)
    if read.total == 0 then
        return path .. " is empty"
    end
    if offset > read.total then
        return string.format("error: offset %d is past the end of %s (%d lines)", offset, path, read.total)
    end
    local rows, size = {}, 0
    for at, line in ipairs(read.lines) do
        local row = string.format("%5d| %s%s\n", offset + at - 1, line, read.cut[at] and TRUNCATED or "")
        if #rows > 0 and size + #row > MAX_BYTES then
            break
        end
        rows[#rows + 1] = row
        size = size + #row
    end
    local text = table.concat(rows)
    local last = offset + #rows - 1
    if last < read.total then
        text = text
            .. string.format("\n[showed lines %d-%d of %d; continue with offset %d]", offset, last, read.total, last + 1)
    end
    return text
end

return {
    description = "Read a text file and return its contents with 1-based line numbers prefixed as `NNN| `. "
        .. "Read a file before editing it so `edit_file` snippets match exactly. Long files come back "
        .. "in pages; when there is more, the output ends with the offset to continue from. The line "
        .. "numbers are display only - never include them in `edit_file` arguments.",
    parameters = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to the file, absolute or relative to the working directory.",
            },
            offset = {
                type = "integer",
                description = "1-based line to start at. Defaults to 1.",
                minimum = 1,
            },
            limit = {
                type = "integer",
                description = "Maximum number of lines to return.",
                minimum = 1,
            },
        },
        required = { "path" },
        additionalProperties = false,
    },
    subject = function(args)
        return field.text(args, "path")
    end,
    policy = "allow",
    display = {
        verb = "Read",
        question = "Would you like to allow uji to `read_file`?",
    },
    run = function(args)
        local missing = field.missing(args, "path")
        if missing then
            return missing
        end
        local path = field.text(args, "path")
        local offset = math.max(field.count(args, "offset") or 1, 1)
        local limit = math.max(field.count(args, "limit") or MAX_LINES, 1)
        local read, err = uji.fs.lines(path, { offset = offset, limit = limit, max_line = MAX_LINE })
        return read and page(path, offset, read) or "error: " .. err
    end,
}
