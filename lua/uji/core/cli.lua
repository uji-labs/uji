local sys = require("uji.sys")

local M = {}

local USAGE = [[A coding agent you can shape with Lua

Usage: uji [COMMAND]

Commands:
  new     Start a new session (the default)
  resume  Resume a session: the latest one here, or --id <ID>
  list    Pick a session in this directory to resume
  delete  Delete a session by id
  run     Run one prompt without the screen and print the answer

Options for run:
  --json                  Print every message as a line of JSON
  --model <PROVIDER/ID>   Use this model
  --effort <LEVEL>        Use this reasoning effort
  --tools <A,B>           Offer only these tools
  --append-prompt <TEXT>  Add text to the end of the system prompt
  --title <TEXT>          Title the session
  --parent <ID>           Save the session under another one

Options:
  -h, --help     Print help
  -V, --version  Print version]]

local SWITCHES = { json = true }

local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

function M.valid_id(id)
    return type(id) == "string" and id:lower():match(UUID) ~= nil
end

function M.fail(message)
    io.stderr:write("uji: error: " .. message .. "\n")
    sys.os.exit(1)
end

function M.session(store, id)
    if not M.valid_id(id) then
        return M.fail("invalid session id: " .. tostring(id))
    end
    return store:session(id) or M.fail("no session with id: " .. id)
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
        elseif SWITCHES[arg:sub(3)] then
            parsed.flags[arg:sub(3)] = true
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
