local json = require("support.json")
local sandbox = require("support.sandbox")
local server = require("support.server")
local sys = require("uji.sys")

local null = sys.json.null
local array = sys.json.array

local IDENTITY = "You are Claude Code, Anthropic's official CLI for Claude."
local HEADERS = { "authorization", "x-api-key", "x-goog-api-key", "anthropic-version", "anthropic-beta", "content-type" }
local EFFORTS = { "off", "low", "high", false }
local RETRYABLE = { [408] = true, [409] = true, [425] = true, [429] = true }

local function call(id, name, arguments)
    return { id = id, name = name, arguments = arguments }
end

local function user(text)
    return { type = "user", text = text }
end

local function tool(id, name, content)
    return { type = "tool", tool_call_id = id, name = name, content = content }
end

local HISTORIES = {
    function()
        return { user("hi") }
    end,
    function()
        return { user("hi"), { type = "assistant", text = "hello" }, user("again") }
    end,
    function()
        return {
            user("fix"),
            {
                type = "assistant",
                text = "",
                tool_calls = {
                    call("c1", "read_file", '{"path":"a.rs"}'),
                    call("c2", "run_command", ""),
                    call("c3", "edit_file", '{"path": "x'),
                },
            },
            tool("c1", "read_file", "contents"),
            tool("c2", "run_command", "out"),
            tool("c3", "edit_file", "error: bad"),
            user("next"),
        }
    end,
    function()
        return {
            { type = "system", text = "sys note" },
            user("q"),
            { type = "shell", command = "ls", output = "a", code = 0 },
            { type = "error", text = "boom" },
            { type = "compaction", summary = "sum", through = 3, files = { "f" } },
            { type = "assistant", text = "a", reasoning = "r" },
            { type = "system", text = "later note" },
            user("q2"),
        }
    end,
}

local function history(at)
    return HISTORIES[at + 1]()
end

local function replayed(assistant)
    return { user("fix"), assistant, tool("c1", "read_file", "contents") }
end

local function anthropic_replay()
    return replayed({
        type = "assistant",
        text = "Reading.",
        reasoning = "plan",
        tool_calls = { call("c1", "read_file", '{"path":"a.rs"}') },
        replay = {
            api = "anthropic",
            model = "claude-opus-4-8",
            content = {
                { type = "thinking", thinking = "plan", signature = "sig" },
                { type = "redacted_thinking", data = "hidden" },
                { type = "text", text = "Reading." },
                { type = "tool_use" },
            },
        },
    })
end

local function responses_replay()
    return replayed({
        type = "assistant",
        text = "Reading.",
        tool_calls = { call("c1", "read_file", '{"path":"a.rs"}') },
        replay = {
            api = "responses",
            model = "gpt-5.5",
            items = {
                {
                    kind = "reasoning",
                    item = { id = "rs_1", type = "reasoning", summary = array({}), encrypted_content = "enc" },
                },
                { kind = "message", id = "msg_1" },
                { kind = "function_call", id = "fc_1" },
            },
        },
    })
end

local function gemini_replay()
    return replayed({
        type = "assistant",
        text = "",
        tool_calls = {
            { id = "c1", name = "read_file", arguments = '{"path":"a.rs"}', signature = "gsig" },
        },
    })
end

local function tools()
    return {
        {
            name = "read_file",
            description = "Read a file.",
            parameters = {
                type = "object",
                properties = { path = { type = "string" }, offset = { type = "integer", minimum = 1 } },
                required = { "path" },
                additionalProperties = false,
            },
        },
        {
            name = "noop",
            description = "Nothing.",
            parameters = { type = "object", properties = {}, required = array({}) },
        },
    }
end

local function base(provider, model, script, overrides)
    local case = {
        provider = provider,
        model = model,
        script = script,
        reasoning = true,
        oauth = false,
        system = "You are a test.",
        messages = history(0),
        tools = tools(),
        effort = "off",
        cache = "off",
        max_output = 8192,
    }
    for key, value in pairs(overrides or {}) do
        case[key] = value
    end
    return case
end

local function openai_cases()
    local out = {}
    for _, provider in ipairs({ "custom", "deepseek", "zhipuai", "openrouter", "moonshotai", "mistral" }) do
        for _, effort in ipairs(EFFORTS) do
            for _, at in ipairs({ 0, 2, 3 }) do
                out[#out + 1] = base(provider, "m", "oa-text", { effort = effort, messages = history(at) })
            end
        end
    end
    for _, options in ipairs({
        { max_tokens_field = false },
        { max_tokens_field = "max_completion_tokens" },
        { tool_result_name = true },
        { cache_key = true, bridge_tool_images = true },
    }) do
        out[#out + 1] = base("custom", "m", "oa-text", { options = options, effort = "medium", messages = history(2) })
    end
    out[#out + 1] = base("deepseek", "m", "oa-text", { reasoning = false, effort = false })
    out[#out + 1] = base("custom", "m", "oa-text", { effort = "high", max_output = 1000 })
    out[#out + 1] = base("custom", "m", "oa-text", { tools = array({}), system = false })
    out[#out + 1] = base("openrouter", "m", "oa-text", { effort = "minimal", messages = history(1) })
    out[#out + 1] = base("custom", "m", "oa-unfinished", { options = { finish_reason = false } })
    for _, script in ipairs({
        "oa-think",
        "oa-reasoning",
        "oa-tools",
        "oa-noid",
        "oa-usage",
        "oa-length",
        "oa-done-only",
        "oa-unfinished",
        "oa-empty",
        "oa-cutcall",
        "oa-garbage",
        "err-429",
        "err-401",
        "err-500",
        "err-400",
    }) do
        out[#out + 1] = base("custom", "m", script)
    end
    return out
end

local function anthropic_cases()
    local out = {}
    for at = 0, 3 do
        for _, effort in ipairs({ "off", "low", "high" }) do
            for _, cache in ipairs({ "off", "short", "long" }) do
                for _, oauth in ipairs({ false, true }) do
                    out[#out + 1] = base("anthropic", "claude-haiku-4-5", "an-text", {
                        effort = effort,
                        cache = cache,
                        oauth = oauth,
                        messages = history(at),
                    })
                end
            end
        end
    end
    for _, model in ipairs({ "claude-sonnet-4-6", "claude-opus-4-8", "claude-fable-5-1" }) do
        for _, effort in ipairs({ "off", "minimal", "high", "max", false }) do
            out[#out + 1] = base("anthropic", model, "an-text", { effort = effort, messages = history(2) })
        end
    end
    for _, model in ipairs({ "claude-opus-4-8", "claude-sonnet-4-6" }) do
        out[#out + 1] = base("anthropic", model, "an-text", { effort = "high", messages = anthropic_replay() })
    end
    out[#out + 1] = base("anthropic", "claude-fable-5-1", "an-text", { effort = "high", oauth = true })
    out[#out + 1] = base("anthropic", "claude-opus-4-8", "an-text", { reasoning = false, effort = false })
    out[#out + 1] = base("anthropic", "claude-haiku-4-5", "an-text", { effort = "high", max_output = 2000 })
    out[#out + 1] = base("anthropic", "claude-haiku-4-5", "an-text", { tools = array({}), system = false, cache = "short" })
    out[#out + 1] = base("anthropic", "claude-haiku-4-5", "an-text", { oauth = true, system = IDENTITY })
    out[#out + 1] = base("anthropic", "claude-haiku-4-5", "an-text", { oauth = true, system = false })
    for _, script in ipairs({
        "an-tools",
        "an-signed",
        "an-limit",
        "an-unfinished",
        "an-ping",
        "err-429",
        "err-401",
        "err-500",
    }) do
        out[#out + 1] = base("anthropic", "claude-opus-4-8", script)
    end
    return out
end

local function gemini_cases()
    local out = {}
    for _, model in ipairs({ "gemini-2.5-flash", "gemini-2.5-pro", "gemini-3-pro-preview", "gemini-3.6-flash" }) do
        for _, at in ipairs({ 0, 2, 3 }) do
            for _, effort in ipairs(EFFORTS) do
                out[#out + 1] = base("google", model, "gm-text", { effort = effort, messages = history(at) })
            end
        end
    end
    out[#out + 1] = base("google", "gemini-3-pro-preview", "gm-text", { messages = gemini_replay() })
    out[#out + 1] = base("google", "gemini-3-pro-preview", "gm-text", { reasoning = false, effort = false })
    out[#out + 1] = base("google", "gemini-2.5-flash", "gm-text", { effort = "high", max_output = 1500 })
    out[#out + 1] = base("google", "gemini-2.5-flash", "gm-text", { tools = array({}), system = false })
    for _, script in ipairs({ "gm-tools", "gm-limit", "gm-unfinished", "err-429", "err-401", "err-500" }) do
        out[#out + 1] = base("google", "gemini-3-pro-preview", script)
    end
    return out
end

local function responses_cases()
    local out = {}
    for _, pair in ipairs({ { "openai", "gpt-5.5" }, { "xai", "grok-4.5" } }) do
        for _, effort in ipairs(EFFORTS) do
            for _, at in ipairs({ 0, 2, 3 }) do
                out[#out + 1] = base(pair[1], pair[2], "rs-text", { effort = effort, messages = history(at) })
            end
        end
    end
    for _, model in ipairs({ "gpt-5.5", "gpt-5" }) do
        out[#out + 1] = base("openai", model, "rs-text", { effort = "high", messages = responses_replay() })
    end
    out[#out + 1] = base("openai", "gpt-4o", "rs-text", { reasoning = false, effort = false })
    out[#out + 1] = base("openai", "gpt-5.5", "rs-text", { tools = array({}), system = false })
    for _, script in ipairs({
        "rs-think",
        "rs-tools",
        "rs-limit",
        "rs-failed",
        "rs-unfinished",
        "err-429",
        "err-401",
        "err-500",
    }) do
        out[#out + 1] = base("openai", "gpt-5.5", script)
    end
    return out
end

local function cases()
    local out = {}
    for _, group in ipairs({ openai_cases(), anthropic_cases(), gemini_cases(), responses_cases() }) do
        for _, case in ipairs(group) do
            out[#out + 1] = case
        end
    end
    return out
end

local function request(case, id, url)
    local auth = { key = "sk-test" }
    if case.oauth then
        auth.oauth = {
            token = "oauth-token",
            headers = { ["anthropic-beta"] = "claude-code-20250219,oauth-2025-04-20" },
            identity_prompt = IDENTITY,
        }
    end
    return {
        model = case.model,
        system = case.system or nil,
        messages = case.messages,
        tools = case.tools,
        effort = case.effort or nil,
        reasoning = case.reasoning,
        max_output = case.max_output,
        cache = case.cache,
        session = "s1",
        provider = { id = case.provider, base_url = url .. "/case/" .. id .. "/" .. case.script .. "/v1" },
        auth = auth,
    }
end

local function event(fields)
    return "data: " .. sys.json.encode(fields)
end

local function oa(delta, finish, usage)
    return event({ choices = { { index = 0, delta = delta, finish_reason = finish or null } }, usage = usage })
end

local function oa_usage(usage)
    return event({ choices = array({}), usage = usage })
end

local function call_delta(index, id, name, arguments)
    local entry = { index = index }
    if id then
        entry.id = id
        entry.type = "function"
    end
    local fn = { name = name, arguments = arguments }
    if next(fn) then
        entry["function"] = fn
    end
    return { tool_calls = { entry } }
end

local function named(kind, fields)
    fields.type = kind
    return "event: " .. kind .. "\n" .. event(fields)
end

local function gm(parts, finish, usage)
    local candidate = {}
    if parts then
        candidate.content = { role = "model", parts = parts }
    end
    candidate.finishReason = finish
    return event({ candidates = { candidate }, usageMetadata = usage })
end

local DONE = "data: [DONE]"

local function block_start(index, block)
    return named("content_block_start", { index = index, content_block = block })
end

local function block_delta(index, delta)
    return named("content_block_delta", { index = index, delta = delta })
end

local function message_start(usage)
    return named("message_start", { message = { usage = usage } })
end

local function message_delta(stop, output)
    return named("message_delta", { delta = { stop_reason = stop }, usage = output and { output_tokens = output } })
end

local MESSAGE_STOP = named("message_stop", {})

local function rs_done(usage)
    return named("response.completed", { response = { status = "completed", usage = usage } })
end

local function scripts()
    local usage = { prompt_tokens = 100, completion_tokens = 20 }
    local rs_usage = { input_tokens = 100, input_tokens_details = { cached_tokens = 40 }, output_tokens = 20 }
    local message = { type = "message", id = "msg_1", role = "assistant" }
    return {
        ["oa-text"] = {
            oa({ role = "assistant", content = "" }),
            oa({ content = "Hello" }),
            oa({ content = " world" }),
            oa({}, "stop"),
            oa_usage(usage),
            DONE,
        },
        ["oa-think"] = {
            ": keepalive",
            oa({ reasoning_content = "Let me " }),
            oa({ reasoning_content = "think." }),
            oa({ content = "Done." }),
            oa({}, "stop", { prompt_tokens = 50, completion_tokens = 9, prompt_tokens_details = { cached_tokens = 30 } }),
            DONE,
        },
        ["oa-tools"] = {
            oa(call_delta(0, "call_a", "read_file", "")),
            oa(call_delta(0, nil, nil, '{"path":')),
            oa(call_delta(0, nil, nil, '"a.rs"}')),
            oa(call_delta(1, "call_b", "run_command", '{"command":"ls"}')),
            oa({}, "tool_calls", { prompt_tokens = 70, completion_tokens = 5, prompt_cache_hit_tokens = 60 }),
            DONE,
        },
        ["oa-reasoning"] = {
            oa({ reasoning = "via reasoning" }),
            oa({ content = "Done." }, "stop"),
            DONE,
        },
        ["oa-noid"] = {
            oa({ content = "x" }),
            oa(call_delta(0, nil, "run_command", '{"command":"pwd"}')),
            oa({}, "tool_calls"),
            DONE,
        },
        ["oa-usage"] = {
            oa({ content = "u" }),
            oa({}, "stop", {
                prompt_tokens = 90,
                completion_tokens = 3,
                cached_tokens = 40,
                prompt_tokens_details = { cache_write_tokens = 10 },
            }),
            DONE,
        },
        ["oa-length"] = { oa({ content = "cut" }), oa({}, "length"), DONE },
        ["oa-done-only"] = { oa({ content = "fine" }), DONE },
        ["oa-unfinished"] = { oa({ content = "half" }) },
        ["oa-empty"] = { oa({}, "stop"), DONE },
        ["oa-cutcall"] = {
            oa(call_delta(0, "c", "edit_file", '{"path": "a')),
            oa({}, "tool_calls"),
            DONE,
        },
        ["oa-garbage"] = {
            "data: {not json",
            oa({ content = "ok" }),
            oa({}, "stop"),
            DONE,
        },
        ["an-text"] = {
            message_start({
                input_tokens = 12,
                output_tokens = 1,
                cache_read_input_tokens = 100,
                cache_creation_input_tokens = 7,
            }),
            block_start(0, { type = "thinking", thinking = "" }),
            block_delta(0, { type = "thinking_delta", thinking = "hmm" }),
            block_start(1, { type = "text", text = "" }),
            block_delta(1, { type = "text_delta", text = "Hi" }),
            block_delta(1, { type = "text_delta", text = " there" }),
            message_delta("end_turn", 15),
            MESSAGE_STOP,
        },
        ["an-tools"] = {
            message_start({ input_tokens = 5, output_tokens = 1 }),
            block_start(0, { type = "text", text = "" }),
            block_delta(0, { type = "text_delta", text = "Reading." }),
            block_start(1, { type = "tool_use", id = "toolu_1", name = "read_file", input = {} }),
            block_delta(1, { type = "input_json_delta", partial_json = '{"pa' }),
            block_delta(1, { type = "input_json_delta", partial_json = 'th": "b.rs"}' }),
            block_start(2, { type = "tool_use", id = "toolu_2", name = "run_command", input = {} }),
            message_delta("tool_use", 30),
            MESSAGE_STOP,
        },
        ["an-limit"] = {
            message_start({ input_tokens = 5 }),
            block_delta(0, { type = "text_delta", text = "cut" }),
            message_delta("max_tokens", 8),
            MESSAGE_STOP,
        },
        ["an-unfinished"] = {
            message_start({ input_tokens = 5 }),
            block_delta(0, { type = "text_delta", text = "half" }),
        },
        ["an-ping"] = {
            'event: ping\ndata: {"type": "ping"}',
            message_start({ input_tokens = 1 }),
            block_delta(0, { type = "text_delta", text = "p" }),
            MESSAGE_STOP,
        },
        ["an-signed"] = {
            message_start({ input_tokens = 5, output_tokens = 1 }),
            block_start(0, { type = "thinking", thinking = "", signature = "" }),
            block_delta(0, { type = "thinking_delta", thinking = "plan" }),
            block_delta(0, { type = "signature_delta", signature = "sig1" }),
            block_start(1, { type = "redacted_thinking", data = "hidden" }),
            block_start(2, { type = "tool_use", id = "toolu_9", name = "read_file", input = {} }),
            block_delta(2, { type = "input_json_delta", partial_json = '{"path": "z"}' }),
            message_delta("tool_use", 30),
            MESSAGE_STOP,
        },
        ["gm-text"] = {
            gm({ { text = "thinking...", thought = true } }),
            gm({ { text = "Hello" } }),
            gm({ { text = " there" } }, "STOP", {
                promptTokenCount = 40,
                candidatesTokenCount = 6,
                cachedContentTokenCount = 10,
                thoughtsTokenCount = 4,
            }),
        },
        ["gm-tools"] = {
            gm({
                { text = "Calling." },
                { functionCall = { name = "read_file", args = { path = "c.rs" } }, thoughtSignature = "gsig" },
                { functionCall = { name = "run_command", args = {} } },
            }, "STOP", { promptTokenCount = 9, candidatesTokenCount = 2 }),
        },
        ["gm-limit"] = { gm({ { text = "cut" } }, "MAX_TOKENS") },
        ["gm-unfinished"] = { gm({ { text = "half" } }) },
        ["rs-text"] = {
            named("response.output_item.added", { output_index = 0, item = message }),
            named("response.output_text.delta", { output_index = 0, delta = "Hello" }),
            named("response.output_text.delta", { output_index = 0, delta = " world" }),
            named("response.output_item.done", { output_index = 0, item = message }),
            rs_done(rs_usage),
        },
        ["rs-think"] = {
            named("response.reasoning_summary_part.added", { output_index = 0, summary_index = 0 }),
            named("response.reasoning_summary_text.delta", { output_index = 0, delta = "Plan" }),
            named("response.reasoning_summary_part.added", { output_index = 0, summary_index = 1 }),
            named("response.reasoning_summary_text.delta", { output_index = 0, delta = "More" }),
            named("response.output_item.done", {
                output_index = 0,
                item = {
                    id = "rs_1",
                    type = "reasoning",
                    summary = { { type = "summary_text", text = "Plan" }, { type = "summary_text", text = "More" } },
                    encrypted_content = "enc",
                },
            }),
            named("response.output_text.delta", { output_index = 1, delta = "Done." }),
            named("response.output_item.done", { output_index = 1, item = message }),
            rs_done(rs_usage),
        },
        ["rs-tools"] = {
            named("response.output_item.done", {
                output_index = 0,
                item = { id = "rs_2", type = "reasoning", summary = array({}), encrypted_content = "enc2" },
            }),
            named("response.output_item.added", {
                output_index = 1,
                item = { type = "function_call", id = "fc_1", call_id = "call_1", name = "read_file", arguments = "" },
            }),
            named("response.function_call_arguments.delta", { output_index = 1, delta = '{"path":' }),
            named("response.function_call_arguments.delta", { output_index = 1, delta = '"a.rs"}' }),
            named("response.output_item.done", {
                output_index = 1,
                item = {
                    type = "function_call",
                    id = "fc_1",
                    call_id = "call_1",
                    name = "read_file",
                    arguments = '{"path":"a.rs"}',
                },
            }),
            rs_done(rs_usage),
        },
        ["rs-limit"] = {
            named("response.output_text.delta", { output_index = 0, delta = "cut" }),
            named("response.incomplete", {
                response = { status = "incomplete", incomplete_details = { reason = "max_output_tokens" } },
            }),
        },
        ["rs-failed"] = {
            named("response.failed", {
                response = { status = "failed", error = { code = "server_error", message = "overloaded" } },
            }),
        },
        ["rs-unfinished"] = {
            named("response.output_text.delta", { output_index = 0, delta = "half" }),
        },
    }
end

local STATUS = {
    ["err-429"] = server.status(429, '{"error": {"message": "slow down"}}', { { "retry-after", "7" } }),
    ["err-401"] = server.status(401, '{"error": "bad key"}'),
    ["err-500"] = server.status(500, "  upstream exploded  "),
    ["err-400"] = server.status(400, string.rep("x", 2500)),
}

local function split(path)
    local parts = {}
    for part in (path .. "/"):gmatch("(.-)/") do
        parts[#parts + 1] = part
    end
    return parts
end

local function script(lines, name)
    if lines[name] then
        return { lines = lines[name] }
    end
    return STATUS[name] or server.status(404, "no script named " .. name)
end

local function observed(incoming)
    local parts = split(incoming.path)
    local headers = {}
    for _, name in ipairs(HEADERS) do
        headers[name] = incoming.headers[name]
    end
    local seen = json.canonical({
        path = "/" .. table.concat({ unpack(parts, 5) }, "/"),
        headers = headers,
        body = incoming.body,
    })
    return parts[3], json.normalize(seen)
end

local function display(failure)
    if failure.kind == "auth" then
        return "authentication rejected (" .. failure.status .. ") - check the api key for this provider", false
    elseif failure.kind == "provider" then
        return "provider: " .. failure.message, false
    end
    local status = failure.status
    local retryable = status == nil or RETRYABLE[status] or (status >= 500 and status < 600)
    local head = status and (status .. ": ") or ""
    return "http: " .. head .. failure.message, retryable, failure.retry_after and math.min(failure.retry_after, 60)
end

local function stream(api, case_request)
    local deltas, result = array({}), nil
    api:stream(case_request, {
        text = function(text)
            deltas[#deltas + 1] = { "text", text }
        end,
        reasoning = function(text)
            deltas[#deltas + 1] = { "reasoning", text }
        end,
        done = function(answer)
            result = {
                ok = {
                    text = answer.text,
                    reasoning = answer.reasoning or null,
                    tool_calls = array(answer.tool_calls),
                    usage = answer.usage or null,
                    replay = answer.replay or null,
                },
            }
        end,
        fail = function(failure)
            local message, retryable, after = display(failure)
            result = { err = { message = message, retryable = retryable, retry_after = after or null } }
        end,
    })
    return json.normalize(json.canonical({ result = result, deltas = deltas }))
end

it("sends and reads the format of each provider", { timeout = 60 }, function()
    local lines = scripts()
    local mock = server.start(function(incoming)
        return script(lines, split(incoming.path)[4] or "")
    end)
    local apis = {}
    for _, provider in ipairs(uji.provider.list()) do
        apis[provider.id] = provider.api
    end
    local listed = cases()
    local results = {}
    for at, case in ipairs(listed) do
        local id = string.format("k%03d", at - 1)
        local api = case.options and uji.api.openai(case.options) or apis[case.provider]
        results[id] = stream(api, request(case, id, mock.url))
    end
    local requests = {}
    for _, incoming in ipairs(mock.requests) do
        local id, seen = observed(incoming)
        requests[id] = seen
    end
    local expected = {}
    for line in sandbox.read(sandbox.fixtures .. "/apis.jsonl"):gmatch("[^\n]+") do
        expected[#expected + 1] = sys.json.decode(line)
    end
    assert.equal(#listed, #expected)
    for _, want in ipairs(expected) do
        local id = want.case
        local sent = json.normalize({ path = want.path, headers = want.headers, body = want.body })
        local problem = json.diff(sent, requests[id])
        assert(problem == nil, "request for " .. id .. ": " .. tostring(problem))
        local answered = json.normalize({ result = want.result, deltas = want.deltas })
        problem = json.diff(answered, results[id])
        assert(problem == nil, "result for " .. id .. ": " .. tostring(problem))
    end
end)
