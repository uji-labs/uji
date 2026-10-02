local class = require("uji.core.class")

local FLAGS = { "bold", "dim", "italic", "underline", "reverse", "strikethrough", "blink" }

local function key_of(spec)
    local parts = { spec.fg or "", spec.bg or "" }
    for _, flag in ipairs(FLAGS) do
        parts[#parts + 1] = spec[flag] and "1" or "0"
    end
    return table.concat(parts, "|")
end

local function merge(base, extra)
    local spec = {}
    for key, value in pairs(base) do
        spec[key] = value
    end
    for key, value in pairs(extra) do
        spec[key] = value
    end
    return spec
end

local Styles = class()

Styles.key_of = key_of

function Styles:init(screen)
    self.screen = screen
    self.ids = {}
    self.specs = { [0] = {} }
    self.derived = {}
    self.revision = -1
    self.palette = {}
end

function Styles:get(spec)
    if spec == nil then
        return 0
    end
    local key = spec.key or key_of(spec)
    local id = self.ids[key]
    if not id then
        local clean = {}
        for _, flag in ipairs(FLAGS) do
            clean[flag] = spec[flag] or nil
        end
        clean.fg, clean.bg = spec.fg, spec.bg
        id = self.screen:style(clean)
        self.ids[key] = id
        self.specs[id] = clean
    end
    return id
end

function Styles:with(id, extra)
    id = id or 0
    local cache = self.derived[id]
    if not cache then
        cache = {}
        self.derived[id] = cache
    end
    local key = key_of(extra)
    local found = cache[key]
    if not found then
        found = self:get(merge(self.specs[id], extra))
        cache[key] = found
    end
    return found
end

function Styles:spec(id)
    return self.specs[id or 0] or {}
end

function Styles:sync(theme)
    if self.revision == theme.revision then
        return self.palette
    end
    self.revision = theme.revision
    local colors = theme.palette
    local confirm = theme.confirm
    local accent = self:get({ fg = colors.accent, bold = true })
    self.palette = {
        plain = 0,
        text = self:get({ fg = colors.text }),
        bold = self:get({ fg = colors.text, bold = true }),
        muted = self:get({ fg = colors.muted }),
        dim = self:get({ fg = colors.muted, dim = true }),
        faint = self:get({ fg = colors.muted, italic = true, dim = true }),
        system = self:get({ fg = colors.muted, italic = true }),
        code = self:get({ fg = colors.code }),
        accent = accent,
        highlight = self:get({ fg = colors.accent }),
        user = self:get({ fg = colors.text, bg = colors.user_bg }),
        selected = self:get({ bg = colors.selected_bg }),
        chosen = self:get({ fg = colors.text, bg = colors.selected_bg }),
        chosen_name = self:get({ fg = colors.accent, bg = colors.selected_bg }),
        chosen_desc = self:get({ fg = colors.muted, bg = colors.selected_bg }),
        error = self:get({ fg = colors.error }),
        notice = self:get({ fg = colors.notice }),
        cursor = self:get({ fg = colors.cursor, blink = theme.cursor_blink }),
        input = self:get({ fg = theme.input or colors.text }),
        border = self:get({ fg = colors.muted }),
        reverse = self:get({ reverse = true }),
        confirm_title = self:get({ fg = confirm.title_color or colors.text, bold = true }),
        confirm_body = self:get({ fg = confirm.body_color or colors.text }),
        confirm_selected = confirm.selected and self:get({ fg = confirm.selected }) or accent,
        confirm_unselected = self:get({ fg = confirm.unselected or colors.muted }),
    }
    return self.palette
end

return Styles
