-- Default uji UI, configured via component objects (nvim-style).

uji.ui.open_win({ view = "messages", split = "top", size = "fill", border = "none" })
uji.ui.open_win({ view = "status", split = "bottom", size = 1 })
uji.ui.open_win({ view = "input", split = "bottom", size = 3 })

uji.ui.input = {
    cursor_blink = true,
}

uji.ui.footer = {
    hint = "ctrl+c exit",
}

uji.ui.suggest = {
    enabled = true,
    max_height = 5,
}

uji.ui.waiting = {
    text = "Working",
    loader = {
        frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        interval_ms = 80,
    },
}
