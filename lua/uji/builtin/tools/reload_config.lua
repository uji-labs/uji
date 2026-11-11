local app = require("uji.core.app")
local config = require("uji.core.config")
local paths = require("uji.core.paths")
local sys = require("uji.sys")

local NAME = "reload_config"
local WAITING = "uji reloads when this turn ends. Say so in one line and end your turn. "
    .. "uji then tells you which notices loading the config raised."
local RELOADED = "uji reloaded and read the config again."
local QUIET = "Loading it raised no notice."
local NOTICES = "Loading it raised these notices:"
local NEXT = "An error in the config is yours to fix before anything else. Otherwise carry on from where you stopped."

local function carried()
    local ok, found = pcall(sys.json.decode, sys.os.carry or "null", { nulls = false })
    return ok and type(found) == "table" and found or {}
end

local state = { granted = carried().reload_tool == true, waiting = false, notices = {}, report = nil }

local function report()
    local rows = { RELOADED }
    if #state.notices == 0 then
        rows[#rows + 1] = QUIET
    else
        rows[#rows + 1] = NOTICES
        for _, notice in ipairs(state.notices) do
            rows[#rows + 1] = "- " .. notice
        end
    end
    rows[#rows + 1] = NEXT
    return table.concat(rows, "\n")
end

local spec = {
    description = "Reload uji so that a change to its config takes effect. uji restarts on this conversation when "
        .. "your turn ends, reads the config again, and then tells you which notices loading it raised, such as an "
        .. "error in init.lua. Call it after you change the config, then end your turn.",
    parameters = { type = "object", properties = {}, additionalProperties = false },
    subject = "config",
    policy = "allow",
    execution = "sequential",
    display = { label = "Reload" },
    run = function()
        if not state.waiting then
            state.waiting = true
            uji.on("turn_finished", function()
                config.reload({ reloaded = true, reload_tool = state.granted or nil })
            end, { name = "uji." .. NAME })
        end
        return WAITING
    end,
}

local function real(path)
    return path and sys.fs.realpath(path) or nil
end

local function in_config()
    local directory, root = real(app.directory()), real(paths.config())
    return directory ~= nil and root ~= nil and sys.fs.inside(directory, root)
end

local function offer()
    if app.command ~= "run" and (state.granted or in_config()) then
        uji.tool.add(NAME, spec)
    end
end

uji.on("session_created", offer, { name = "uji." .. NAME })
uji.on("session_resumed", offer, { name = "uji." .. NAME })

if carried().reloaded == true then
    local listening = uji.on("notice", function(notice)
        state.notices[#state.notices + 1] = notice.text
    end)
    uji.context.add("reloaded", function()
        local text = state.report
        state.report = nil
        return text and { at = "turn", text = text } or nil
    end, { priority = 22 })
    uji.schedule(function()
        uji.off("notice", listening)
        state.report = report()
        app.agent:wake()
    end)
end

return {
    grant = function()
        state.granted = true
        offer()
    end,
}
