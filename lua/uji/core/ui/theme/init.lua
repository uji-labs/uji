local class = require("uji.core.class")
local default = require("uji.themes.default")()
local model = require("uji.core.model")
local notices = require("uji.core.notices")
local Themes = require("ito").Themes

local MODULE = "uji.themes."
local SAVED = "ui.theme"

local OPTIONS = {
    theme = "theme",
    show_thinking = "boolean",
    suggest = { enabled = "boolean" },
}

local CHECKS = {
    boolean = function(value, path)
        if type(value) ~= "boolean" then
            error(path .. " must be true or false", 0)
        end
    end,
    theme = function(value, path)
        if type(value) ~= "string" and type(value) ~= "table" then
            error(path .. " must be a theme name or a theme table", 0)
        end
    end,
}

local function check(value, rules, path)
    if type(value) ~= "table" then
        error((path == "" and "options" or path) .. " must be a table", 0)
    end
    for key, item in pairs(value) do
        local rule = rules[key]
        local at = path == "" and tostring(key) or path .. "." .. tostring(key)
        if rule == nil then
            error("unknown option: " .. at, 0)
        end
        if type(rule) == "table" then
            check(item, rule, at)
        else
            CHECKS[rule](item, at)
        end
    end
end

local function load(name)
    local module = MODULE .. name
    local ok, found = pcall(require, module)
    if not ok then
        if tostring(found):find("module '" .. module .. "' not found", 1, true) then
            error("no theme named " .. name .. " (a theme lives in lua/uji/themes/" .. name .. ".lua)", 0)
        end
        error("theme " .. name .. ": " .. tostring(found), 0)
    end
    return found
end

local Theme = class(Themes)

function Theme:init()
    Themes.init(self, { default = default, load = load })
    self.show_thinking = false
    self.suggest_enabled = true
end

function Theme:configure(opts)
    check(opts, OPTIONS, "")
    local selection = opts.theme == nil and self.selection or opts.theme
    local tokens = self:build(selection)
    if opts.show_thinking ~= nil then
        self.show_thinking = opts.show_thinking
    end
    if opts.suggest and opts.suggest.enabled ~= nil then
        self.suggest_enabled = opts.suggest.enabled
    end
    self:use(selection, tokens)
end

function Theme:save(name)
    model.set_setting(SAVED, name)
end

function Theme:restore()
    local name = model.setting(SAVED)
    if not name then
        return
    end
    local ok, err = pcall(self.select, self, name)
    if not ok then
        notices.push("saved theme: " .. tostring(err))
    end
end

function Theme:toggle_thinking()
    self.show_thinking = not self.show_thinking
    self:bump()
    return self.show_thinking
end

return Theme
