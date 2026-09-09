-- Default uji UI, configured via component objects (nvim-style).

uji.ui.open_win({ view = "messages", split = "top", size = "fill", border = "none" })
uji.ui.open_win({ view = "status", split = "bottom", size = 1 })
uji.ui.open_win({ view = "input", split = "bottom", size = 3 })

local waiting_text = "Working"

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

local function render_footer()
    uji.footer.clear()
    if uji.status.state() == "working" then
        local frame = uji.status.loader_frame()
        if frame ~= "" then
            uji.footer.push(frame)
        end
        uji.footer.push(waiting_text)
        local elapsed = uji.status.elapsed()
        if elapsed then
            uji.footer.push(string.format("(%ds)", math.floor(elapsed)))
        end
    else
        local provider = uji.status.provider()
        local model = uji.status.model()
        if provider then
            uji.footer.push(provider .. "/" .. model)
        end
    end
    uji.footer.push("ctrl+c exit")
end

uji.on("status_changed", render_footer)
uji.on("tick", render_footer)
render_footer()
