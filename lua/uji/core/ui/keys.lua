local text = require("ito").text

local M = {}

local SINGLE = "^(" .. text.CHAR .. ")$"

local NAMES = {
    cr = "enter",
    enter = "enter",
    ["return"] = "enter",
    esc = "esc",
    escape = "esc",
    bs = "backspace",
    backspace = "backspace",
    del = "delete",
    delete = "delete",
    tab = "tab",
    ["s-tab"] = "backtab",
    backtab = "backtab",
    left = "left",
    right = "right",
    up = "up",
    down = "down",
    home = "home",
    ["end"] = "end",
    pageup = "pageup",
    pgup = "pageup",
    pagedown = "pagedown",
    pgdn = "pagedown",
    insert = "insert",
    space = " ",
    lt = "<",
    gt = ">",
}

local LABELS = {
    [" "] = "Space",
    enter = "CR",
    esc = "Esc",
    backspace = "BS",
    delete = "Del",
    tab = "Tab",
    backtab = "S-Tab",
    left = "Left",
    right = "Right",
    up = "Up",
    down = "Down",
    home = "Home",
    ["end"] = "End",
    pageup = "PageUp",
    pagedown = "PageDown",
    insert = "Insert",
}

function M.chord(key, ctrl, alt, shift)
    return {
        key = key,
        ctrl = ctrl == true,
        alt = alt == true,
        shift = key == "backtab" or shift == true,
    }
end

function M.is_char(chord)
    return chord.key:match(SINGLE) ~= nil
end

function M.typed(chord)
    return M.is_char(chord) and not chord.ctrl and not chord.alt
end

local function parse_key(name)
    local lowered = name:lower()
    if NAMES[lowered] then
        return NAMES[lowered]
    end
    local number = tonumber(lowered:match("^f(%d+)$"))
    if number and number >= 1 and number <= 12 then
        return "f" .. number
    end
    return name:match(SINGLE)
end

function M.parse(spec)
    if type(spec) ~= "string" then
        return nil
    end
    spec = text.trim(spec)
    if spec == "" then
        return nil
    end
    if spec:sub(1, 1) ~= "<" or spec:sub(-1) ~= ">" then
        local char = spec:match(SINGLE)
        return char and M.chord(char)
    end
    local rest = spec:sub(2, -2)
    local ctrl, alt, shift = false, false, false
    while #rest >= 2 do
        local prefix, tail = rest:sub(1, 2):lower(), rest:sub(3)
        if prefix == "c-" then
            ctrl = true
        elseif prefix == "a-" or prefix == "m-" then
            alt = true
        elseif prefix == "s-" and tail:lower() ~= "tab" then
            shift = true
        else
            break
        end
        rest = tail
    end
    local key = parse_key(rest)
    return key and M.chord(key, ctrl, alt, shift)
end

function M.describe(chord)
    local key = chord.key
    local name = LABELS[key] or (key:match("^f%d+$") and key:upper()) or key
    if M.is_char(chord) and key ~= " " and not chord.ctrl and not chord.alt and not chord.shift then
        return name
    end
    local out = { "<" }
    if chord.ctrl then
        out[#out + 1] = "C-"
    end
    if chord.alt then
        out[#out + 1] = "A-"
    end
    if chord.shift and key ~= "backtab" then
        out[#out + 1] = "S-"
    end
    out[#out + 1] = name
    out[#out + 1] = ">"
    return table.concat(out)
end

function M.id(chord)
    if M.is_char(chord) then
        return M.describe({ key = chord.key:lower(), ctrl = chord.ctrl, alt = chord.alt, shift = false })
    end
    return M.describe(chord)
end

function M.from_event(event)
    return M.chord(event.key, event.ctrl, event.alt, event.shift)
end

function M.capture(chord)
    return {
        key = M.describe(chord),
        char = M.is_char(chord) and chord.key or nil,
        ctrl = chord.ctrl,
        alt = chord.alt,
        shift = chord.shift,
    }
end

return M
