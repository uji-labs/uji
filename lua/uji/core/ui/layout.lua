local M = {}

local function vertical(split)
    return split == "top" or split == "bottom"
end

function M.rect(x, y, width, height)
    return { x = x, y = y, width = math.max(width, 0), height = math.max(height, 0) }
end

local rect = M.rect

local function carve(area, split, take)
    if split == "top" then
        return rect(area.x, area.y, area.width, take), rect(area.x, area.y + take, area.width, area.height - take)
    end
    if split == "bottom" then
        local height = math.max(area.height - take, 0)
        return rect(area.x, area.y + height, area.width, take), rect(area.x, area.y, area.width, height)
    end
    if split == "left" then
        return rect(area.x, area.y, take, area.height), rect(area.x + take, area.y, area.width - take, area.height)
    end
    local width = math.max(area.width - take, 0)
    return rect(area.x + width, area.y, take, area.height), rect(area.x, area.y, width, area.height)
end

local function resolve(extent, available)
    if extent.percent then
        return math.floor(available * math.min(extent.percent, 100) / 100)
    end
    return math.min(extent.cells, available)
end

function M.centered(area, width, height)
    width = math.min(width, area.width)
    height = math.min(height, area.height)
    return rect(area.x + math.floor((area.width - width) / 2), area.y + math.floor((area.height - height) / 2), width, height)
end

function M.float(area, float)
    return M.centered(area, resolve(float.width, area.width), resolve(float.height, area.height))
end

function M.layout(area, windows)
    local rects = {}
    local remaining = area
    for index, window in ipairs(windows) do
        if window.float then
            rects[index] = M.float(area, window.float)
        else
            local down = vertical(window.split)
            local reserved, fills = 0, 1
            for later = index + 1, #windows do
                local other = windows[later]
                if not other.float and vertical(other.split) == down then
                    local size = other:effective_size()
                    if type(size) == "number" then
                        reserved = reserved + size
                    else
                        fills = fills + 1
                    end
                end
            end
            local available = down and remaining.height or remaining.width
            local size = window:effective_size()
            local take
            if type(size) == "number" then
                take = math.min(size, available)
            else
                take = math.floor(math.max(available - reserved, 0) / fills)
            end
            rects[index], remaining = carve(remaining, window.split, take)
        end
    end
    return rects
end

function M.inner(area, border, padding)
    local x, y, width, height = area.x, area.y, area.width, area.height
    if border == "plain" or border == "rounded" then
        x, y, width, height = x + 1, y + 1, width - 2, height - 2
    elseif border == "horizontal" then
        y, height = y + 1, height - 2
    end
    padding = padding or 0
    return rect(x, y + padding, width, height - padding * 2)
end

return M
