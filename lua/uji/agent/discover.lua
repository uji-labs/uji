local auth = require("uji.auth")
local catalog = require("uji.catalog")
local notices = require("uji.notices")
local sys = require("uji.sys")
local task = require("uji.task")

local M = {}

function M.windows(provider)
    local credentials = auth.resolve(provider)
    local headers = {}
    if credentials and credentials.key then
        headers.Authorization = "Bearer " .. credentials.key
    end
    local response = sys.net.request({
        url = provider.base_url:gsub("/+$", "") .. "/model/info",
        headers = headers,
    })
    if not response or response.status < 200 or response.status >= 300 then
        return nil
    end
    local ok, info = pcall(sys.json.decode, response.body, { nulls = false })
    if not ok or type(info) ~= "table" or type(info.data) ~= "table" then
        return nil
    end
    local found = {}
    for _, entry in ipairs(info.data) do
        local limits = entry.model_info or {}
        if type(entry.model_name) == "string" and (limits.max_input_tokens or limits.max_output_tokens) then
            found[#found + 1] = {
                model = entry.model_name,
                context = limits.max_input_tokens,
                output = limits.max_output_tokens,
            }
        end
    end
    return found
end

function M.start(on_change)
    for _, provider in ipairs(catalog.all()) do
        if provider.origin == "registered" and provider.base_url ~= "" then
            task.spawn(function()
                local found = M.windows(provider)
                if not found then
                    return
                end
                local changed = catalog.set_windows(provider.id, found)
                if changed > 0 then
                    notices.push(string.format(
                        "%s: corrected %d model window%s from the endpoint",
                        provider.id,
                        changed,
                        changed == 1 and "" or "s"
                    ))
                    if on_change then
                        on_change()
                    end
                end
            end)
        end
    end
end

return M
