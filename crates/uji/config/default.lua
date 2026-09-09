-- Default uji UI, configured via component objects (nvim-style).

uji.ui.messages = {
    border = "none",
}

uji.ui.input = {
    height = 3,
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
        mode = "braille",
        interval_ms = 80,
    },
}

local function render_status()
    local parts = {}
    if uji.status.state() == "working" then
        local frame = uji.status.loader_frame()
        if frame ~= "" then
            table.insert(parts, frame)
        end
        table.insert(parts, uji.ui.waiting.text)
        local elapsed = uji.status.elapsed()
        if elapsed then
            table.insert(parts, string.format("(%ds)", math.floor(elapsed)))
        end
    else
        local provider = uji.status.provider()
        local model = uji.status.model()
        if provider then
            table.insert(parts, provider .. "/" .. model)
        end
    end
    uji.ui.set_status(table.concat(parts, " "))
end

uji.on("status_changed", render_status)
uji.on("tick", render_status)
render_status()
