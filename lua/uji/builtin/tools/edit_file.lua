local field = require("uji.builtin.tools.field")

local function occurrences(text, old)
    local count, at = 0, 1
    while true do
        local first, last = text:find(old, at, true)
        if not first then
            return count
        end
        count, at = count + 1, last + 1
    end
end

local function replace(text, old, new, all)
    local parts, at = {}, 1
    repeat
        local first, last = text:find(old, at, true)
        if not first then
            break
        end
        parts[#parts + 1] = text:sub(at, first - 1)
        parts[#parts + 1] = new
        at = last + 1
    until not all
    parts[#parts + 1] = text:sub(at)
    return table.concat(parts)
end

local function line_of(text, at)
    local _, newlines = text:sub(1, at - 1):gsub("\n", "")
    return newlines + 1
end

local function apply(args)
    local missing = field.missing(args, "path", "old_string")
    if missing then
        return nil, missing
    end
    local path = field.text(args, "path")
    local old = field.text(args, "old_string")
    local new = field.text(args, "new_string")
    local all = args.replace_all == true
    if old == new then
        return nil, "error: old_string and new_string are identical"
    end
    local text, err = uji.fs.read(path)
    if not text then
        return nil, "error: " .. err
    end
    local first = text:find(old, 1, true)
    if not first then
        return nil,
            "error: old_string was not found in "
                .. path
                .. ". Read the file again and copy the "
                .. "snippet exactly, without line-number prefixes."
    end
    local count = occurrences(text, old)
    if count > 1 and not all then
        return nil,
            string.format("error: old_string matches %d places in %s. ", count, path)
                .. "Add surrounding lines to make it unique, or pass replace_all: true."
    end
    return { path = path, before = text, after = replace(text, old, new, all), all = all, count = count, line = line_of(text, first) }
end

uji.tool.add("edit_file", {
    description = "Replace an exact snippet of an existing file, leaving the rest untouched. This is the tool "
        .. "to use for changing code. `old_string` must reproduce the file's current text byte for "
        .. "byte, including indentation and newlines, and must appear exactly once unless "
        .. "`replace_all` is true - include a few surrounding lines to make it unique. Do not include "
        .. "the `NNN| ` line-number prefixes that read_file adds. To delete code, pass an empty "
        .. "`new_string`.",
    parameters = {
        type = "object",
        properties = {
            path = {
                type = "string",
                description = "Path to the file to edit, absolute or relative to the working directory.",
            },
            old_string = {
                type = "string",
                description = "Exact text to find, copied verbatim from the file.",
            },
            new_string = {
                type = "string",
                description = "Text to put in its place. Empty string deletes the snippet.",
            },
            replace_all = {
                type = "boolean",
                description = "Replace every occurrence instead of requiring exactly one. Defaults to false.",
            },
        },
        required = { "path", "old_string", "new_string" },
        additionalProperties = false,
    },
    subject = field.subject("path"),
    policy = "ask",
    display = {
        verb = "Edited",
        question = "Would you like to make the following edit?",
        preview = function(args)
            local edit = apply(args)
            return edit and uji.diff(edit.before, edit.after, edit.path)
        end,
    },
    run = function(args)
        local edit, err = apply(args)
        if not edit then
            return err
        end
        local written, failure = uji.fs.write(edit.path, edit.after)
        if not written then
            return "error: " .. failure
        end
        local text = edit.all and string.format("edited %s: replaced %d occurrences", edit.path, edit.count)
            or string.format("edited %s at line %d", edit.path, edit.line)
        return { text = text, diff = uji.diff(edit.before, edit.after, edit.path) }
    end,
})
