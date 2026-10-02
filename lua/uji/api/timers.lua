local notices = require("uji.core.notices")
local task = require("uji.core.task")

uji.notify = notices.push

uji.schedule = function(callback)
    task.schedule(callback)
end

uji.defer = function(seconds, callback)
    if type(seconds) ~= "number" or seconds < 0 then
        error("defer needs a number of seconds", 2)
    end
    return task.defer(seconds, callback)
end
