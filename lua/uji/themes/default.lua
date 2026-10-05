local ito = require("ito")

local COLORS = {
    text = ito.rgb(0xd4d4d4),
    muted = ito.rgb(0x808080),
    code = ito.rgb(0xe0af68),
    accent = ito.Color.cyan,
    user_bg = ito.rgb(0x343541),
    selected_bg = ito.rgb(0x3a3a4a),
    cursor = ito.Color.white,
    error = ito.Color.red,
    notice = ito.Color.red,
}

local function styles(c)
    local S = ito.TextStyle
    return {
        plain = S({}),
        text = S({ foreground = c.text }),
        bold = S({ foreground = c.text, bold = true }),
        muted = S({ foreground = c.muted }),
        dim = S({ foreground = c.muted, dim = true }),
        faint = S({ foreground = c.muted, italic = true, dim = true }),
        system = S({ foreground = c.muted, italic = true }),
        code = S({ foreground = c.code }),
        accent = S({ foreground = c.accent, bold = true }),
        highlight = S({ foreground = c.accent }),
        user = S({ foreground = c.text, background = c.user_bg }),
        selected = S({ background = c.selected_bg }),
        chosen = S({ foreground = c.text, background = c.selected_bg }),
        chosen_name = S({ foreground = c.accent, background = c.selected_bg }),
        chosen_desc = S({ foreground = c.muted, background = c.selected_bg }),
        error = S({ foreground = c.error }),
        notice = S({ foreground = c.notice }),
        cursor = S({ foreground = c.cursor, blink = true }),
        input = S({ foreground = c.text }),
        border = S({ foreground = c.muted }),
        reverse = S({ reverse = true }),
        confirm_title = S({ foreground = c.text, bold = true }),
        confirm_body = S({ foreground = c.text }),
        confirm_selected = S({ foreground = c.accent, bold = true }),
        confirm_unselected = S({ foreground = c.muted }),
        heading1 = S({ foreground = c.accent, bold = true }),
        heading2 = S({ foreground = c.accent, bold = true }),
        heading3 = S({ foreground = c.text, bold = true }),
        heading4 = S({ foreground = c.text, bold = true }),
        heading5 = S({ foreground = c.text, bold = true }),
        heading6 = S({ foreground = c.text, bold = true }),
        strong = S({ bold = true }),
        emphasis = S({ italic = true }),
        strikethrough = S({ strikethrough = true }),
        link = S({ underline = true }),
        table_head = S({ bold = true }),
        code_keyword = S({ foreground = c.accent }),
        code_string = S({ foreground = c.code }),
        code_number = S({ foreground = c.code }),
        code_comment = S({ foreground = c.muted, italic = true, dim = true }),
        selection = S({ reverse = true }),
    }
end

local SYMBOLS = {
    spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    tool = "•",
    branch = "└",
    more = "…",
    shell = "!",
    rule = "─",
    notice = "!",
    thinking = "│",
    queued = "›",
    running = "⋯",
    jump = "↓",
    bullets = { "•", "◦", "▪" },
    quote = "│",
    column = "│",
    task_done = "[x]",
    task_open = "[ ]",
    cursor = "█",
    mask = "•",
    pointer = "›",
    prompt = ">",
}

local BORDERS = {
    plain = {
        top_left = "┌",
        top_right = "┐",
        bottom_left = "└",
        bottom_right = "┘",
        horizontal = "─",
        vertical = "│",
    },
    rounded = {
        top_left = "╭",
        top_right = "╮",
        bottom_left = "╰",
        bottom_right = "╯",
        horizontal = "─",
        vertical = "│",
    },
}

local TEXT = {
    confirm_yes = "Yes",
    confirm_no = "No",
    confirm_allow = "proceed",
    confirm_deny = "and tell uji what to do differently",
    called = "Called",
    exit = "exit",
    compacted = "compacted",
    hidden = "+%d lines",
    jump = "Jump to bottom",
    ordered = "%d.",
    current = "(current)",
    range = "%d–%d of %d",
    scroll = "lines %d-%d of %d, scroll for more",
    sessions_title = "Sessions in %s",
    sessions_empty = "No sessions in current directory",
    column_title = "TITLE",
    column_updated = "UPDATED",
    column_id = "ID",
    key_move = "↑/↓",
    key_open = "enter",
    key_quit = "esc",
    navigate = "navigate",
    resume = "resume",
    quit = "quit",
    working = "Working (%ds)",
    copied = "copied %d line(s)",
    copied_terminal = "copied %d line(s) via the terminal",
    pasted_lines = "[paste #%d +%d lines]",
    pasted_chars = "[paste #%d %d chars]",
    image = "[image #%d]",
}

local LIMITS = {
    spinner_interval = 0.08,
    suggest_rows = 5,
    tool_preview = 8,
    argument_preview = 200,
    message_gap = 1,
    section_gap = 1,
    bottom_gap = 1,
    indent = 2,
    rule_width = 60,
    block_gap = 1,
    reply_margin = 1,
    input_rows = 10,
    select_rows = 12,
    suggest_name = 12,
    preview_min = 24,
    sessions_updated = 14,
    sessions_id = 36,
    float_width = 90,
    float_height = 80,
    flash = 1,
    paste_lines = 1,
    paste_chars = 80,
}

local function merged(base, changes)
    local out = {}
    for key, value in pairs(base) do
        out[key] = value
    end
    for key, value in pairs(changes or {}) do
        out[key] = value
    end
    return out
end

return function(changes)
    changes = changes or {}
    local colors = merged(COLORS, changes.colors)
    local extra = type(changes.styles) == "function" and changes.styles(colors) or changes.styles
    return {
        name = changes.name or "default",
        colors = colors,
        styles = merged(styles(colors), extra),
        symbols = merged(SYMBOLS, changes.symbols),
        borders = merged(BORDERS, changes.borders),
        text = merged(TEXT, changes.text),
        limits = merged(LIMITS, changes.limits),
        options = merged({}, changes.options),
        views = merged({}, changes.views),
    }
end
