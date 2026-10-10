local auth = require("uji.core.auth")
local catalog = require("uji.core.catalog")
local task = require("uji.core.task")

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
    login = task.callback(function(id)
        return auth.login(provider(id))
    end),
}
