local tool = require("uji.tool")

for _, name in ipairs({ "read_file", "edit_file", "write_file", "run_command" }) do
    tool.add(name, require("uji.tools." .. name))
end
