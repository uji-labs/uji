-- Default uji UI, configured via windows + buffers (nvim-style).

uji.ui.open_win({ view = "messages", split = "top", size = "fill", wrap = true })
local status = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.open_win({ view = "input", split = "bottom", size = 3, border = "horizontal" })

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

local waiting_text = "Working"

local function render_status()
    if uji.status.state() == "working" then
        local elapsed = math.floor(uji.status.elapsed() or 0)
        uji.ui.set_lines(status, {
            {
                { text = uji.status.loader_frame() .. " ", color = "cyan", bold = true },
                { text = waiting_text .. " (" .. elapsed .. "s)", color = "#808080" },
            },
        })
    else
        local provider = uji.status.provider()
        local model = uji.status.model()
        if provider then
            uji.ui.set_lines(status, { { text = provider .. "/" .. model, color = "#808080" } })
        else
            uji.ui.clear(status)
        end
    end
end

uji.on("status_changed", render_status)
uji.on("tick", render_status)
render_status()
