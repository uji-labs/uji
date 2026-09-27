uji.ui.open_win({ view = "messages", split = "top", size = "fill", wrap = true })
uji.ui.open_win({ view = "input", split = "bottom", size = "auto", border = "horizontal" })
uji.ui.open_win({ view = "modal", split = "bottom", size = "auto" })
local activity = uji.ui.open_win({ split = "bottom", size = 0, padding = 1 })

uji.ui.configure({
    input = { cursor_blink = true },
    suggest = { enabled = true, max_height = 5 },
    waiting = {
        loader = {
            frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
            interval = 0.08,
        },
    },
})

uji.tool.policy({
    run_command = {
        deny = { "/^rm\\s+-rf/" },
    },
})

local waiting_text = "Working"

local function render_activity()
    if uji.status.state() == "working" then
        uji.ui.set_size(activity, 3)
        local elapsed = math.floor(uji.status.elapsed() or 0)
        uji.ui.set_lines(activity, {
            {
                { text = uji.status.loader_frame() .. " ", color = "cyan", bold = true },
                { text = waiting_text .. " (" .. elapsed .. "s)", color = "#808080" },
            },
        })
    else
        uji.ui.set_size(activity, 0)
    end
end

uji.on("status_changed", render_activity)
uji.on("loader_ticked", render_activity)

uji.keymap.add("normal", "<A-e>", { command = "effort" })
