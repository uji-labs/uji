local text = require("ito").text

local function ordered(listed)
    table.sort(listed, function(left, right)
        local live, other = left.state == "running", right.state == "running"
        if live ~= other then
            return live
        end
        return left.id > right.id
    end)
    return listed
end

uji.command.add("jobs", {
    desc = "list background jobs and stop one",
    handler = function()
        local listed = uji.jobs.list()
        if #listed == 0 then
            uji.notify("no background jobs")
            return
        end
        local job = uji.ui.pick({
            title = "Jobs",
            items = ordered(listed),
            label = function(item)
                return "job " .. item.id .. "  " .. item.status .. "  " .. item.command
            end,
            preview = function(item)
                return text.lines(item.tail)
            end,
        })
        if job and job.state == "running" then
            uji.jobs.stop(job.id)
        end
    end,
})
