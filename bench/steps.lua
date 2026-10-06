local agent = require("support.agent")
local app = require("uji.core.app")
local class = require("uji.core.class")
local screen = require("support.ui")
local server = require("support.server")
local sys = require("uji.sys")
local ito = require("ito")
local ui = require("uji.core.ui")

local POLL = 0.01
local NUMBER = "{n}"
local INDENT = "{indent}"
local INDENT_UNIT = "  "
local WORDS = "%S*%s*"

local function templated(spec)
    if type(spec) == "string" then
        return spec:find(NUMBER, 1, true) ~= nil or spec:find(INDENT, 1, true) ~= nil
    end
    if type(spec) == "table" then
        for _, value in pairs(spec) do
            if templated(value) then
                return true
            end
        end
    end
    return false
end

local function fill(spec, index)
    if type(spec) == "string" then
        local filled = spec:gsub(NUMBER, tostring(index))
        if filled:find(INDENT, 1, true) then
            filled = filled:gsub(INDENT, INDENT_UNIT:rep(index - 1))
        end
        return filled
    end
    if type(spec) ~= "table" then
        return spec
    end
    local out = {}
    for key, value in pairs(spec) do
        out[key] = fill(value, index)
    end
    return out
end

local function words(source)
    local out = {}
    for word in source:gmatch(WORDS) do
        if word ~= "" then
            out[#out + 1] = word
        end
    end
    return out
end

local function pieces(source, size)
    if not size then
        return { source }
    end
    local out = {}
    for at = 1, #source, size do
        out[#out + 1] = source:sub(at, at + size - 1)
    end
    return out
end

local function delta(fields, finish)
    return { choices = { { index = 0, delta = fields, finish_reason = finish or sys.json.null } } }
end

local Context = class()

local GENERATORS = {}

function GENERATORS.fixture(ctx, spec)
    return ctx:fixture(spec.fixture)
end

function GENERATORS.random(_, spec)
    return sys.random(spec.random)
end

function GENERATORS.bytes(_, spec)
    return string.char(unpack(spec.bytes))
end

function GENERATORS.value(ctx, spec)
    return ctx:value(assert(ctx.values[spec.value], "no value named " .. spec.value))
end

function GENERATORS.join(ctx, spec)
    local parts = {}
    for index, part in ipairs(spec.join) do
        parts[index] = ctx:value(part)
    end
    return table.concat(parts)
end

GENERATORS["repeat"] = function(ctx, spec)
    local template, times = spec["repeat"], spec.times
    local separator = spec.separator or ""
    if not templated(template) then
        local value = ctx:value(template)
        if type(value) == "string" then
            return value:rep(times, separator)
        end
    end
    local out = {}
    for index = 1, times do
        out[index] = ctx:value(fill(template, index))
    end
    return type(out[1]) == "string" and table.concat(out, separator) or out
end

function Context:init(dir, values)
    self.dir = dir
    self.values = values or {}
    self.frames = 0
    self.fixtures = {}
    self.generated = {}
end

function Context:fixture(name)
    if not self.fixtures[name] then
        self.fixtures[name] = assert(sys.fs.read(self.dir .. "/" .. name))
    end
    return self.fixtures[name]
end

function Context:value(spec)
    if type(spec) ~= "table" then
        return spec
    end
    if self.generated[spec] then
        return self.generated[spec]
    end
    for kind, generate in pairs(GENERATORS) do
        if spec[kind] ~= nil then
            self.generated[spec] = generate(self, spec)
            return self.generated[spec]
        end
    end
    local out = {}
    for key, value in pairs(spec) do
        out[key] = self:value(value)
    end
    return out
end

function Context:frame()
    ui:render()
    self.frames = self.frames + 1
end

function Context:cold()
    app.session.stored = nil
    ui.scroll:to_end()
    self:frame()
end

function Context:reply(spec)
    if spec.lines then
        return { lines = spec.lines }
    end
    if spec.drip then
        return server.drip("data: " .. sys.json.encode(delta({ content = self:value(spec.drip) })), spec.every)
    end
    local chunks = {}
    for _, piece in ipairs(pieces(self:value(spec.reasoning or ""), spec.chunk)) do
        if piece ~= "" then
            chunks[#chunks + 1] = delta({ reasoning_content = piece })
        end
    end
    local answer = self:value(spec.text or "")
    for _, piece in ipairs(spec.words and words(answer) or pieces(answer, spec.chunk)) do
        chunks[#chunks + 1] = delta({ content = piece })
    end
    chunks[#chunks + 1] = delta({}, "stop")
    return server.events(chunks)
end

function Context:serve(script)
    local served = agent.serve(script)
    agent.provider(served.url, 1000000)
    uji.model.use({ provider = "test", model = "m" })
    agent.allow_all()
end

function Context:turn(prompt)
    local finished = sys.promise()
    local listener = uji.on("turn_finished", function()
        finished:resolve()
    end)
    uji.session.submit(self:value(prompt))
    finished:await()
    uji.off("turn_finished", listener)
end

local STEPS = {}

function STEPS.press(ctx, key)
    screen.press(key)
    ctx:frame()
end

function STEPS.type(ctx, typed)
    for char in ctx:value(typed):gmatch(ito.text.CHAR) do
        screen.typing(char)
        ctx:frame()
    end
end

function STEPS.input(ctx, draft)
    ui:set_input(ctx:value(draft))
    ctx:frame()
end

function STEPS.paste(ctx, pasted)
    ui:paste(ctx:value(pasted))
    ctx:frame()
end

function STEPS.clear(ctx)
    ui:clear_input()
    ctx:frame()
end

function STEPS.history(ctx, spec)
    spec = ctx:value(spec)
    local reply, output = spec.reply, spec.output
    for index = 1, spec.turns do
        local call = { id = "call" .. index, name = "read_file", arguments = '{"path":"src/main.rs"}' }
        app.session:append({ type = "user", text = "Question " .. index })
        app.session:append({ type = "assistant", text = "", tool_calls = { call } })
        app.session:append({ type = "tool", tool_call_id = call.id, name = call.name, content = output })
        app.session:append({ type = "assistant", text = reply })
    end
end

function STEPS.cold(ctx)
    ctx:cold()
end

function STEPS.top(ctx)
    ctx:cold()
    local _, height = ui.screen:size()
    local before
    while ui.scroll.moved ~= before do
        before = ui.scroll.moved
        ui.scroll:scroll(-height)
        ctx:frame()
    end
end

function STEPS.wheel(ctx, spec)
    for _ = 1, spec.steps do
        ui.scroll:scroll(-spec.rows)
        ctx:frame()
    end
    for _ = 1, spec.steps do
        ui.scroll:scroll(spec.rows)
        ctx:frame()
    end
end

function STEPS.append(ctx, message)
    app.session:append(ctx:value(message))
end

function STEPS.show(ctx, reply)
    reply = ctx:value(reply)
    app.session:append({ type = "assistant", text = reply })
    ctx:cold()
    ui:clear_stream()
    ui:delta({ kind = "text", text = reply })
    ui.stream:reveal_all()
    ctx:frame()
    ui:clear_stream()
end

function STEPS.stream(ctx, reply)
    ui:clear_stream()
    for _, word in ipairs(words(ctx:value(reply))) do
        ui:delta({ kind = "text", text = word })
        ui.stream:reveal_step()
        ctx:frame()
    end
    ui:clear_stream()
end

function STEPS.serve(ctx, spec)
    local reply = ctx:reply(spec)
    ctx:serve(function()
        return reply
    end)
end

function STEPS.turn(ctx, prompt)
    ctx:turn(prompt)
end

function STEPS.submit(ctx, prompt)
    uji.session.submit(ctx:value(prompt))
end

function STEPS.interrupt()
    uji.session.interrupt()
end

function STEPS.idle()
    while app.agent.state ~= "idle" or #app.agent.queue > 0 do
        sys.sleep(POLL)
    end
end

function STEPS.sleep(_, seconds)
    sys.sleep(seconds)
end

function STEPS.thinking(ctx, shown)
    if ui.theme.show_thinking ~= shown then
        ui:toggle_thinking()
    end
    ctx:frame()
end

function STEPS.file(ctx, spec)
    assert(sys.fs.write(app.session.directory .. "/" .. spec.path, ctx:value(spec.text)))
end

function STEPS.call(ctx, spec)
    local calls = {}
    for index, call in ipairs(ctx:value(spec.calls or { spec })) do
        calls[index] = { call.tool, sys.json.encode(call.args) }
    end
    ctx:serve(function(round)
        return round == 0 and server.tool_calls(round, calls) or server.text("done")
    end)
    ctx:turn("use the tools")
    if spec.ok then
        local results = agent.tool_results(agent.messages())
        local last = results[#results]
        assert(type(last) == "string" and not last:find("^error:"), tostring(last):sub(1, 200))
    end
end

function STEPS.answer(_, expected)
    local answer = agent.last_answer(agent.messages())
    assert(answer == expected, "the reply was " .. tostring(answer))
end

STEPS["repeat"] = function(ctx, steps, step)
    for _ = 1, step.times do
        ctx:run(steps)
    end
end

function Context:step(step)
    for key, arg in pairs(step) do
        local run = STEPS[key]
        if run then
            return run(self, arg, step)
        end
    end
    error("unknown step " .. sys.json.encode(step), 0)
end

function Context:prepare(steps)
    for _, step in ipairs(steps or {}) do
        for key, arg in pairs(step) do
            if key == "repeat" then
                self:prepare(arg)
            else
                self:value(arg)
            end
        end
    end
end

function Context:run(steps)
    for _, step in ipairs(steps or {}) do
        self:step(step)
    end
end

return Context
