-- Default uji UI.
-- Message history fills the top (Pi-style blocks); input bar + status footer
-- at the bottom.

uji.ui.open_win("messages", {
    split = "top",
    size = "fill",
    border = "none",
})

uji.ui.open_win("status", {
    split = "bottom",
    size = 1,
    border = "none",
})

uji.ui.open_win("input", {
    split = "bottom",
    size = 3,
    border = "none",
})
