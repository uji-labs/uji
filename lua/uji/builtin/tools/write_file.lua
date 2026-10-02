local field = require("uji.builtin.tools.field")

local function line_count(text)
    local _, newlines = text:gsub("\n", "")
    if text ~= "" and text:sub(-1) ~= "\n" then
        return newlines + 1
    end
    return newlines
end

uji.tool.add("write_file", {
    description = "Write a file from scratch, creating parent directories as needed. This replaces the entire "
        .. "file, so use it for new files only. To change an existing file use `edit_file` instead - "
        .. "overwriting loses everything you did not include.",
    parameters = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to write, absolute or relative to the working directory.",
            },
            content = {
                type = "string",
                description = "Complete contents of the file.",
            },
        },
        required = { "path", "content" },
        additionalProperties = false,
    },
    subject = field.subject("path"),
    policy = "ask",
    display = {
        verb = "Wrote",
        question = "Would you like to write the following file?",
    },
    run = function(args)
        local missing = field.missing(args, "path")
        if missing then
            return missing
        end
        local path = field.text(args, "path")
        local content = field.text(args, "content")
        local written, err = uji.fs.write(path, content)
        if not written then
            return "error: " .. err
        end
        local verb = written.created and "created" or "overwrote"
        return string.format("%s %s (%d lines)", verb, path, line_count(content))
    end,
})
