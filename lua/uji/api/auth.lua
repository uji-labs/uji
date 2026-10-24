local auth = require("uji.core.auth")
local catalog = require("uji.core.catalog")
local DeviceLogin = require("uji.core.ui.views.device_login")
local task = require("uji.core.task")
local ui = require("uji.core.ui")

local function provider(id)
    local found = catalog.get(id)
    if not found then
        error("no provider is registered as " .. tostring(id), 3)
    end
    return found
end

uji.auth = {
    configure = auth.configure,
    authenticated = function(id)
        return auth.authenticated(provider(id))
    end,
    save_key = function(id, key)
        if type(key) ~= "string" or key == "" then
            error("uji.auth.save_key needs a non-empty key", 2)
        end
        local saved, err = auth.save_key(provider(id).id, key)
        if not saved then
            return nil, err
        end
        return true
    end,
    remove = function(id)
        return auth.remove(provider(id).id)
    end,
    login = function(id, opts, on_done)
        if type(opts) == "function" then
            on_done, opts = opts, nil
        end
        local modal
        local function close()
            if modal then
                modal:close()
            end
        end
        local run = task.callback(function()
            local ok, err = auth.login(provider(id), opts, function(flow)
                modal = ui:present(DeviceLogin(flow))
                return function()
                    modal:wait()
                end
            end)
            close()
            return ok, err
        end)
        if on_done then
            local cancel = run(on_done)
            return function()
                cancel()
                close()
            end
        end
        return run()
    end,
}
