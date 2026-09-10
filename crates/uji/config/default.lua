-- Default uji UI, configured via windows + buffers (nvim-style).

uji.ui.open_win({ view = "messages", split = "top", size = "fill", wrap = true })
local status = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.open_win({ view = "input", split = "bottom", size = 3, border = "horizontal" })
local activity = uji.ui.open_win({ split = "bottom", size = 0 })

uji.ui.configure({
    input = { cursor_blink = true },
    suggest = { enabled = true, max_height = 5 },
    waiting = {
        loader = {
            frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
            interval_ms = 80,
        },
    },
})

uji.tool.policy = {
    run_command = {
        deny = { "/^rm -rf/", "/^git push/" },
    },
}

local waiting_text = "Working"

local function render_status()
    local provider = uji.status.provider()
    local model = uji.status.model()
    if provider then
        uji.ui.set_lines(status, { { text = provider .. "/" .. model, color = "#808080" } })
    else
        uji.ui.clear(status)
    end
end

local function render_activity()
    if uji.status.state() == "working" then
        uji.ui.set_size(activity, 1)
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

uji.on("status_changed", function()
    render_status()
    render_activity()
end)
uji.on("tick", render_activity)
render_status()
