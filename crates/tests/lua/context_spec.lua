local view = require("uji.core.agent.view")

local function stored(seq, message)
    return { seq = seq, message = message }
end

local function text(message)
    return message.text or message.content or message.output or message.summary
end

it("never sends a shell message to the model", function()
    local context = view.build({
        stored(0, { type = "user", text = "hello" }),
        stored(1, { type = "shell", command = "cat secrets.env", output = "TOKEN=hunter2", code = 0 }),
    })
    assert.equal(1, #context)
    for _, message in ipairs(context) do
        assert.is_nil(text(message):find("hunter2", 1, true), "shell output leaked into the context")
    end
end)

it("never sends a job message to the model", function()
    local context = view.build({
        stored(0, { type = "user", text = "hello" }),
        stored(1, { type = "job", id = 1, command = "npm run build", output = "built in 2.1s", code = 0, state = "finished" }),
    })
    assert.equal(1, #context)
    for _, message in ipairs(context) do
        assert.is_nil(text(message):find("built in 2.1s", 1, true), "job output leaked into the context")
    end
end)

it("cuts the history a compaction summarised", function()
    local context = view.build({
        stored(0, { type = "user", text = "ancient history" }),
        stored(1, { type = "compaction", summary = "they said hello", through = 0, files = { "src/main.rs" } }),
        stored(2, { type = "user", text = "recent" }),
    })
    assert.equal(2, #context)
    assert.truthy(text(context[1]):find("they said hello", 1, true))
    assert.is_nil(text(context[1]):find("ancient history", 1, true))
    assert.equal("recent", text(context[2]))
end)
