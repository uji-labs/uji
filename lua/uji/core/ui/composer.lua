local class = require("uji.core.class")
local Line = require("uji.core.ui.line")
local Pastes = require("uji.core.ui.paste")

local Composer = class()

function Composer:init()
    self.line = Line()
    self.pastes = Pastes()
    self.recall = nil
end

function Composer:text()
    return self.line.text
end

function Composer:edit(change)
    self.recall = nil
    change(self.line)
    self.pastes:prune(self.line.text)
end

function Composer:paste(value)
    local cleaned = Pastes.clean(value)
    if cleaned == "" then
        return
    end
    local inserted = self.pastes:stash(cleaned)
    self:edit(function(line)
        line:insert(inserted)
    end)
end

function Composer:attach(image)
    local marker = self.pastes:attach(image)
    self:edit(function(line)
        line:insert(marker)
    end)
end

function Composer:backspace()
    local id, width = self.pastes:marker_ending_at(self.line.text:sub(1, self.line.cursor))
    if id then
        self.pastes:forget(id)
        self:edit(function(line)
            line:delete_before(width)
        end)
        return
    end
    self:edit(Line.backspace)
end

function Composer:clear()
    self.pastes:clear()
    self:edit(Line.clear)
end

function Composer:set(value)
    self:edit(function(line)
        line:set(value)
    end)
end

function Composer:take()
    self.recall = nil
    local value = self.line:take()
    local images = self.pastes:images(value)
    local expanded = self.pastes:expand(value)
    self.pastes:clear()
    return expanded, images
end

function Composer:continue_line()
    local value = self.line.text
    if value:sub(-1) ~= "\\" or self.line.cursor ~= #value then
        return false
    end
    self:edit(function(line)
        line:backspace()
        line:insert("\n")
    end)
    return true
end

function Composer:up()
    return self.line:up()
end

function Composer:down()
    return self.line:down()
end

function Composer:recall_prev(lookup)
    local at = self.recall and self.recall.at + 1 or 0
    local found = lookup(at)
    if not found then
        return false
    end
    if self.recall then
        self.recall.at = at
    else
        self.recall = { at = at, draft = self.line:take(), pastes = self.pastes }
        self.pastes = Pastes()
    end
    self.line:set(found)
    return true
end

function Composer:recall_next(lookup)
    local recall = self.recall
    if not recall then
        return false
    end
    if recall.at == 0 then
        self.recall = nil
        self.pastes = recall.pastes
        self.line:set(recall.draft)
        return true
    end
    local found = lookup(recall.at - 1)
    if not found then
        return false
    end
    recall.at = recall.at - 1
    self.line:set(found)
    return true
end

return Composer
