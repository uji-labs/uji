local field = require("uji.builtin.tools.field")
local words = require("uji.utils.text")

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
                description = "Path to write: absolute, relative to the working directory, or starting with `~/`.",
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
    path = true,
    policy = "ask",
    display = {
        label = "Write",
        question = "Would you like to write the following file?",
        preview = function(args)
            local path = field.text(args, "path")
            return uji.diff(uji.fs.read(path) or "", field.text(args, "content"), path)
        end,
    },
    run = function(args)
        local missing = field.missing(args, "path")
        if missing then
            return missing
        end
        local path = field.text(args, "path")
        local content = field.text(args, "content")
        local before = uji.fs.read(path)
        local written, err = uji.fs.write(path, content)
        if not written then
            return "error: " .. err
        end
        local verb = written.created and "created" or "overwrote"
        local lines = line_count(content)
        return {
            text = string.format("%s %s (%d lines)", verb, path, lines),
            diff = before and uji.diff(before, content, path),
            summary = "Wrote " .. words.count(lines, "line"),
        }
    end,
})
