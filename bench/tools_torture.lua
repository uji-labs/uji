local app = require("uji.core.app")
local scenario = require("scenario")
local sys = require("uji.sys")

local MEGABYTE = 1024 * 1024
local LINE = "the quick brown fox jumps over the lazy dog, again and again and again\n"

local function file(name, data)
    local path = app.session.directory .. "/" .. name
    assert(sys.fs.write(path, data))
    return path
end

local function worked(result)
    assert(type(result) == "string" and not result:find("^error:"), tostring(result):sub(1, 200))
end

scenario.open()

torture("read a 50 MB file", function()
    file("big.txt", string.rep(LINE, math.ceil(50 * MEGABYTE / #LINE)))
    worked(scenario.call("read_file", { path = "big.txt" }))
end, { budget = 5 })

torture("read a file with a 10 MB line", function()
    file("wide.txt", string.rep("x", 10 * MEGABYTE) .. "\nshort\n")
    worked(scenario.call("read_file", { path = "wide.txt" }))
end, { budget = 5 })

torture("read 1 MB of random bytes", function()
    file("noise.bin", sys.random(MEGABYTE))
    scenario.call("read_file", { path = "noise.bin" })
end, { budget = 5 })

torture("edit the end of a 20 MB file", function()
    file("huge.txt", string.rep(LINE, math.ceil(20 * MEGABYTE / #LINE)) .. "the unique ending\n")
    worked(scenario.call("edit_file", { path = "huge.txt", old_string = "the unique ending", new_string = "a new ending" }))
end, { budget = 5 })

torture("write a 10 MB file", function()
    worked(scenario.call("write_file", { path = "written.txt", content = string.rep(LINE, math.ceil(10 * MEGABYTE / #LINE)) }))
end, { budget = 10 })
