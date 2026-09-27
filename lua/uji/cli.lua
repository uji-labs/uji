local M = {}

local USAGE = [[A coding agent you can shape with Lua

Usage: uji [COMMAND]

Commands:
  new     Start a new session (the default)
  resume  Resume a session: the latest one here, or --id <ID>
  list    Pick a session in this directory to resume
  delete  Delete a session by id

Options:
  -h, --help     Print help
  -V, --version  Print version]]

local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

function M.valid_id(id)
    return type(id) == "string" and id:lower():match(UUID) ~= nil
end

function M.parse(args)
    local parsed = { command = nil, flags = {} }
    local index = 2
    while index <= #args do
        local arg = args[index]
        local flag, value = arg:match("^%-%-([%w%-]+)=(.*)$")
        if flag then
            parsed.flags[flag] = value
        elseif arg == "--help" or arg == "-h" then
            parsed.command = "help"
        elseif arg == "--version" or arg == "-V" then
            parsed.command = "version"
        elseif arg:sub(1, 2) == "--" then
            parsed.flags[arg:sub(3)] = args[index + 1]
            index = index + 1
        elseif not parsed.command then
            parsed.command = arg
        else
            parsed.positional = parsed.positional or {}
            parsed.positional[#parsed.positional + 1] = arg
        end
        index = index + 1
    end
    parsed.command = parsed.command or "new"
    return parsed
end

M.USAGE = USAGE

return M
