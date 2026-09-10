-- Default uji UI, configured via windows + buffers (nvim-style).

uji.ui.open_win({ view = "messages", split = "top", size = "fill", wrap = true })
local status = uji.ui.open_win({ split = "bottom", size = 1 })
uji.ui.open_win({ view = "input", split = "bottom", size = 3, border = "horizontal" })
local activity = uji.ui.open_win({ split = "bottom", size = 0, padding = 1 })

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

uji.on("tool_call", function(event)
    if event.name == "run_command" then
        local cmd = event.arguments.command or ""
        if string.match(cmd, "^rm %-rf") then
            return { deny = "Refusing to run rm -rf" }
        end
        return { ask = true }
    end
    -- reads and writes fall through to the default policy (allow / ask)
    return nil
end)

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

uji.on("status_changed", function()
    render_status()
    render_activity()
end)
uji.on("tick", render_activity)
render_status()

-- Keybindings. Every key is remappable per mode: normal, suggest, select,
-- prompt, confirm. A binding is either a builtin action name, a slash command
-- via { command = "models" }, or nil to unbind the key entirely.
--
-- Actions: quit, interrupt, submit, clear_input, backspace, cursor_left,
-- cursor_right, cursor_start, cursor_end, scroll_up, scroll_down, page_up,
-- page_down, scroll_top, scroll_bottom, modal_up, modal_down, modal_accept,
-- modal_cancel, suggest_complete, confirm_allow, confirm_deny, confirm_toggle,
-- nothing.
--
-- uji.keymap.set("normal", "<C-p>", { command = "models" })
-- uji.keymap.set("normal", "<C-u>", "clear_input")
-- uji.keymap.set("normal", "<C-c>", nil)
-- uji.keymap.list()
