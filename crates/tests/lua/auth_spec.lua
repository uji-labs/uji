local auth = require("uji.core.auth")
local catalog = require("uji.core.catalog")
local command = require("uji.core.command")
local device = require("uji.core.auth.device")
local model = require("uji.core.model")
local oauth = require("uji.core.auth.oauth")
local process = require("uji.core.system.process")
local Server = require("support.server")
local sys = require("uji.sys")
local tables = require("uji.core.tables")
local wait = require("support.wait")

local ID = "device-test"
local CODE = { device_auth_id = "device-id", user_code = "ABCD-EFGH", interval = "1" }
local APPROVED = { authorization_code = "auth-code", code_verifier = "device-verifier" }

local function jwt(claims)
    return "header." .. sys.base64.encode(sys.json.encode(claims), { url = true, pad = false }) .. ".signature"
end

local function grant()
    return {
        access_token = jwt({ exp = oauth.now() + 3600 }),
        id_token = jwt({ ["https://api.openai.com/auth"] = { chatgpt_account_id = "chatgpt-account" } }),
        refresh_token = "refresh",
    }
end

local function json(value)
    return Server.status(200, sys.json.encode(value))
end

local function provider(handler)
    local server = Server.start(handler)
    local config = tables.copy(catalog.get("openai").oauth)
    config.token_url = server.url .. "/oauth/token"
    config.device = {
        code_url = server.url .. "/usercode",
        poll_url = server.url .. "/poll",
        verification_url = server.url .. "/device",
        redirect_uri = server.url .. "/deviceauth/callback",
    }
    local api = getmetatable(catalog.get("openai").api)({ oauth_url = server.url .. "/codex/responses" })
    uji.provider.add({ id = ID, name = ID, api = api, base_url = server.url, oauth = config })
    return catalog.get(ID), server
end

-- Answers the usercode request with CODE, so a test writes only its own step.
local function device_provider(handler)
    return provider(function(request)
        if request.path == "/usercode" then
            return json(CODE)
        end
        return handler(request)
    end)
end

local function form(raw)
    local result = {}
    local function decode(text)
        return (text:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end))
    end
    for key, value in raw:gmatch("([^=&]+)=([^&]*)") do
        result[decode(key)] = decode(value)
    end
    return result
end

it("uses device sign-in without an API organization for a ChatGPT model request", function()
    local polls, exchanges = 0, {}
    local issued = grant()
    local chosen, server = provider(function(request)
        if request.path == "/usercode" then
            assert.same({ client_id = catalog.get("openai").oauth.client_id }, request.body)
            return json(CODE)
        elseif request.path == "/poll" then
            assert.same({ device_auth_id = CODE.device_auth_id, user_code = CODE.user_code }, request.body)
            polls = polls + 1
            if polls < 3 then
                return Server.status(polls == 1 and 403 or 404, "pending")
            end
            return json(APPROVED)
        elseif request.path == "/codex/responses" then
            assert.equal("Bearer " .. issued.access_token, request.headers.authorization)
            assert.equal("chatgpt-account", request.headers["chatgpt-account-id"])
            assert.equal("uji", request.headers.originator)
            assert.is_nil(request.body.max_output_tokens)
            assert.is_false(request.body.store)
            assert.is_true(request.body.stream)
            assert.equal("developer", request.body.input[1].role)
            assert.equal("Say hello.", request.body.input[1].content)
            assert.equal("hi", request.body.input[2].content[1].text)
            return Server.events({
                { type = "response.output_text.delta", delta = "Hello" },
                { type = "response.completed", response = { usage = { input_tokens = 2, output_tokens = 1 } } },
            })
        end
        assert.equal("/oauth/token", request.path)
        assert.equal("application/x-www-form-urlencoded", request.headers["content-type"])
        local fields = form(request.raw)
        exchanges[#exchanges + 1] = fields
        if fields.grant_type == "authorization_code" then
            return json(issued)
        end
        return Server.status(401, '{"error":{"message":"Invalid ID token: missing organization_id","code":"invalid_subject_token"}}')
    end)
    process.open = function()
        error("device sign-in must not open a browser")
    end
    sys.net.listen = function()
        error("device sign-in must not bind a callback port")
    end
    local messages = {}
    uji.on("notice", function(notice)
        messages[#messages + 1] = notice.text
    end)
    local done = sys.promise()
    local cancel = uji.auth.login(ID, { method = "device" }, function(ok, err)
        done:resolve(ok, err)
    end)
    assert.equal("function", type(cancel))
    local ok, err = done:await()
    assert.is_nil(err)
    assert.is_true(ok)
    assert.equal(3, polls)
    assert.same({
        grant_type = "authorization_code",
        client_id = chosen.oauth.client_id,
        code = "auth-code",
        code_verifier = "device-verifier",
        redirect_uri = server.url .. "/deviceauth/callback",
    }, exchanges[1])
    assert.equal(1, #exchanges)
    local stored = auth.credentials():get(ID)
    assert.equal("oauth", stored.type)
    assert.equal(issued.access_token, stored.access)
    assert.equal("refresh", stored.refresh)
    assert.equal("chatgpt-account", stored.account_id)
    assert.is_true(stored.expires_at > oauth.now() + 3200)
    uji.model.use({ provider = ID, model = "gpt-5.5" })
    local answer, failure = model.generate({ system = "Say hello.", messages = { { type = "user", text = "hi" } } })
    assert.is_nil(failure)
    assert.equal("Hello", answer.text)
    assert.equal(1, answer.usage.output)
    local message = table.concat(messages, "\n")
    assert.truthy(message:find(server.url .. "/device", 1, true))
    assert.truthy(message:find(CODE.user_code, 1, true))
    assert.is_nil(message:find(CODE.device_auth_id, 1, true))
end)

it("accepts the usercode spelling and numeric polling intervals", function()
    local chosen = provider(function()
        return json({ device_auth_id = "device", usercode = "1234", interval = 0 })
    end)
    local flow = device.start(chosen.oauth)
    assert.equal("1234", flow.code)
    assert.equal(1, flow.interval)
end)

it("waits five seconds between polls when the device code omits the interval", function()
    local chosen = provider(function()
        return json({ device_auth_id = "device", user_code = "1234" })
    end)
    assert.equal(5, device.start(chosen.oauth).interval)
end)

it("rejects malformed device codes without saving a credential", function()
    local body
    provider(function()
        return Server.status(200, body)
    end)
    for _, value in ipairs({
        "not json",
        "null",
        sys.json.encode({ user_code = "1234" }),
        sys.json.encode({ device_auth_id = "device", user_code = "" }),
        sys.json.encode({ device_auth_id = "device", user_code = "1234", interval = "bad" }),
        sys.json.encode({ device_auth_id = "device", user_code = "1234", interval = -1 }),
    }) do
        body = value
        local ok, err = uji.auth.login(ID, { method = "device" })
        assert.is_nil(ok)
        assert.truthy(err:find("unexpected body", 1, true))
        assert.is_nil(auth.credentials():get(ID))
    end
end)

it("explains when device sign-in is unavailable", function()
    provider(function()
        return Server.status(404, "unavailable")
    end)
    local ok, err = uji.auth.login(ID, { method = "device" })
    assert.is_nil(ok)
    assert.truthy(err:find("ChatGPT security settings", 1, true))
end)

it("stops on rejected polling responses and preserves the saved credential", function()
    local status, polls = 0, 0
    device_provider(function()
        polls = polls + 1
        return Server.status(status, "private server details")
    end)
    assert(uji.auth.save_key(ID, "existing"))
    for _, code in ipairs({ 400, 401, 429, 500 }) do
        status, polls = code, 0
        local ok, err = uji.auth.login(ID, { method = "device" })
        assert.is_nil(ok)
        assert.equal("device sign-in returned " .. code, err)
        assert.equal(1, polls)
        assert.equal("existing", auth.credentials():get(ID).key)
    end
end)

it("rejects an approval missing the PKCE verifier", function()
    provider(function(request)
        return json(request.path == "/usercode" and CODE or { authorization_code = "code" })
    end)
    local ok, err = uji.auth.login(ID, { method = "device" })
    assert.is_nil(ok)
    assert.equal("device sign-in returned an unexpected body", err)
    assert.is_nil(auth.credentials():get(ID))
end)

it("expires pending device codes even while an HTTP request is waiting", function()
    local chosen = device_provider(function()
        sys.sleep(1)
        return json(APPROVED)
    end)
    local flow = device.start(chosen.oauth)
    flow.expires_at = sys.os.clock() + 0.05
    local began = sys.os.clock()
    local ok, err = pcall(device.login, chosen.oauth, flow)
    assert.is_false(ok)
    assert.truthy(err:find("expired after 15 minutes", 1, true))
    assert.is_true(sys.os.clock() - began < 0.5)
    assert.is_nil(auth.credentials():get(ID))
end)

it("does not poll an already expired device code", function()
    local chosen, server = provider(function()
        return json(CODE)
    end)
    local flow = device.start(chosen.oauth)
    flow.expires_at = 0
    assert.is_false(pcall(device.login, chosen.oauth, flow))
    assert.equal(1, #server.requests)
end)

it("cancels device polling without saving or invoking the callback", function()
    local ui = require("uji.core.ui")
    local polls, completed = 0, false
    device_provider(function()
        polls = polls + 1
        return Server.status(403, "pending")
    end)
    local cancel = uji.auth.login(ID, { method = "device" }, function()
        completed = true
    end)
    wait.eventually(function()
        return polls > 0
    end)
    assert.equal(CODE.user_code, ui.modal.code)
    cancel()
    assert.is_nil(ui.modal)
    sys.sleep(1.1)
    assert.equal(1, polls)
    assert.is_false(completed)
    assert.is_nil(auth.credentials():get(ID))
end)

it("keeps the device code visible beyond the notification timer until sign-in finishes", { size = { 40, 14 } }, function()
    local notices = require("uji.core.notices")
    local screen = require("support.ui")
    local ui = require("uji.core.ui")
    local approved = false
    device_provider(function(request)
        if request.path == "/poll" then
            return approved and json(APPROVED) or Server.status(403, "pending")
        end
        return json(grant())
    end)
    local done = sys.promise()
    uji.auth.login(ID, { method = "device" }, function(ok, err)
        done:resolve(ok, err)
    end)
    wait.eventually(function()
        return ui.modal and ui.modal.code == CODE.user_code
    end)
    notices.push("another notification")
    ui:take_notices()
    sys.sleep(ui.theme.tokens.limits.flash + 0.1)
    assert.truthy(screen.find(CODE.user_code), "the complete code remains visible")
    assert.truthy(screen.find("Waiting for sign-in"))
    screen.press("enter")
    assert.equal(CODE.user_code, ui.modal.code)
    approved = true
    local ok, err = done:await()
    assert.is_nil(err)
    assert.is_true(ok)
    assert.is_nil(ui.modal)
    assert.is_nil(screen.find(CODE.user_code))
end)

it("cancels device sign-in with Escape and clears the code", { size = { 40, 14 } }, function()
    local screen = require("support.ui")
    local ui = require("uji.core.ui")
    local polls = 0
    device_provider(function()
        polls = polls + 1
        return Server.status(403, "pending")
    end)
    local done = sys.promise()
    uji.auth.login(ID, { method = "device" }, function(ok, err)
        done:resolve(ok, err)
    end)
    wait.eventually(function()
        return polls > 0
    end)
    screen.press("esc")
    local ok, err = done:await()
    assert.is_nil(ok)
    assert.equal("sign-in canceled", err)
    assert.is_nil(ui.modal)
    assert.is_nil(auth.credentials():get(ID))
    local stopped = polls
    sys.sleep(1.1)
    assert.equal(stopped, polls)
end)

it("clears the device code when sign-in fails", function()
    device_provider(function()
        return Server.status(401, "denied")
    end)
    local ok, err = uji.auth.login(ID, { method = "device" })
    assert.is_nil(ok)
    assert.truthy(err:find("device sign-in returned 401", 1, true))
    assert.is_nil(require("uji.core.ui").modal)
end)

it("keeps the existing credential if the final token exchange fails", function()
    device_provider(function(request)
        if request.path == "/poll" then
            return json(APPROVED)
        end
        return Server.status(401, "denied")
    end)
    assert(uji.auth.save_key(ID, "existing"))
    local ok, err = uji.auth.login(ID, { method = "device" })
    assert.is_nil(ok)
    assert.truthy(err:find("token exchange returned 401", 1, true))
    assert.equal("existing", auth.credentials():get(ID).key)
end)

it("leaves state out of the device sign-in exchange", function()
    local fields
    local chosen = device_provider(function(request)
        if request.path == "/poll" then
            return json(APPROVED)
        end
        fields = form(request.raw)
        return json(grant())
    end)
    chosen.oauth.state = "verifier"
    assert.is_true(uji.auth.login(ID, { method = "device" }))
    assert.is_nil(fields.state)
end)

it("reports a credential save failure after a successful device exchange", function()
    device_provider(function(request)
        if request.path == "/poll" then
            return json(APPROVED)
        end
        return json(grant())
    end)
    auth.credentials().save = function()
        return nil, "disk full"
    end
    local ok, err = uji.auth.login(ID, { method = "device" })
    assert.is_nil(ok)
    assert.equal("signed in but could not save the credential: disk full", err)
end)

it("retains browser login and the callback shorthand", function()
    local fields
    local chosen = provider(function(request)
        fields = form(request.raw)
        return json(grant())
    end)
    chosen.oauth.state = "verifier"
    local closed, opened = false, nil
    oauth.start = function()
        return {
            redirect_uri = "http://localhost/callback",
            verifier = "browser-verifier",
            state = "browser-state",
            url = function()
                return "https://example.test/authorize"
            end,
            wait = function()
                return { code = "browser-code", state = "browser-state" }
            end,
        }, {
            close = function()
                closed = true
            end,
        }
    end
    process.open = function(url)
        opened = url
    end
    local done = sys.promise()
    uji.auth.login(ID, function(ok, err)
        done:resolve(ok, err)
    end)
    assert.is_true(done:await())
    assert.is_true(closed)
    assert.equal("https://example.test/authorize", opened)
    assert.equal("browser-verifier", fields.code_verifier)
    assert.equal("browser-state", fields.state)
    assert.equal("oauth", auth.credentials():get(ID).type)
    assert.equal("chatgpt-account", auth.credentials():get(ID).account_id)
end)

it("refreshes ChatGPT access tokens and retains account metadata when omitted", function()
    local refreshed, expected_refresh, exchanges = nil, "refresh", 0
    local chosen, server = provider(function(request)
        if request.path == "/oauth/token" then
            exchanges = exchanges + 1
            assert.same({
                grant_type = "refresh_token",
                client_id = catalog.get("openai").oauth.client_id,
                refresh_token = expected_refresh,
            }, form(request.raw))
            return json(refreshed)
        end
        assert.equal("/codex/responses", request.path)
        assert.equal("Bearer " .. refreshed.access_token, request.headers.authorization)
        assert.equal("chatgpt-account", request.headers["chatgpt-account-id"])
        return Server.events({
            { type = "response.output_text.delta", delta = "refreshed" },
            { type = "response.completed", response = {} },
        })
    end)
    uji.model.use({ provider = ID, model = "gpt-5.5" })
    local stored = { type = "oauth", access = "expired", refresh = "refresh", account_id = "chatgpt-account" }
    for _, rotation in ipairs({ "rotated", "" }) do
        stored.expires_at = oauth.now() - 1
        assert(auth.credentials():save(ID, stored))
        refreshed = { access_token = jwt({ exp = oauth.now() + 3600 }), refresh_token = rotation }
        local answer, failure = model.generate({ messages = { { type = "user", text = "hi" } } })
        assert.is_nil(failure)
        assert.equal("refreshed", answer.text)
        stored = auth.credentials():get(ID)
        assert.equal("rotated", stored.refresh)
        assert.equal("chatgpt-account", stored.account_id)
        assert.is_true(stored.expires_at > oauth.now() + 3200)
        expected_refresh = "rotated"
    end
    assert.equal(2, exchanges)
    assert.equal(4, #server.requests)
    assert.equal(stored.access, auth.resolve(chosen).oauth.token)
end)

it("preserves the credential and skips model requests if refresh is rejected", function()
    local chosen, server = provider(function(request)
        assert.equal("/oauth/token", request.path)
        return Server.status(401, "refresh token expired")
    end)
    local stored = { type = "oauth", access = "expired", refresh = "refresh", account_id = "chatgpt-account", expires_at = 1 }
    assert(auth.credentials():save(ID, stored))
    uji.model.use({ provider = chosen.id, model = "gpt-5.5" })
    local answer, failure = model.generate({ messages = { { type = "user", text = "hi" } } })
    assert.is_nil(answer)
    assert.truthy(failure.message:find("token refresh returned 401", 1, true))
    assert.same(stored, auth.credentials():get(ID))
    assert.equal(1, #server.requests)
end)

it("requires a ChatGPT account ID and accepts it from either token", function()
    local issued
    local chosen = provider(function()
        return json(issued)
    end)
    for _, id in ipairs({ "invalid", jwt({}), jwt({ ["https://api.openai.com/auth"] = "invalid" }) }) do
        issued = { access_token = "access", id_token = id }
        local ok, err = pcall(oauth.exchange, chosen.oauth, "code", "redirect", "verifier")
        assert.is_false(ok)
        assert.equal("sign-in did not return an account ID; please sign in again", err)
    end
    issued = { access_token = jwt({ exp = oauth.now() + 3600, ["https://api.openai.com/auth"] = { chatgpt_account_id = "account" } }) }
    assert.equal("account", oauth.exchange(chosen.oauth, "code", "redirect", "verifier").account_id)
end)

it("retains expiry and refresh behavior for OAuth providers with opaque tokens", function()
    local issued = { access_token = "opaque", expires_in = 3600, refresh_token = "original" }
    local chosen = provider(function()
        return json(issued)
    end)
    chosen.oauth.account_id_claim = nil
    local stored = oauth.exchange(chosen.oauth, "code", "redirect", "verifier")
    assert.is_nil(stored.account_id)
    assert.is_true(stored.expires_at > oauth.now() + 3200)
    issued = { access_token = "new-opaque", expires_in = 1800 }
    local refreshed = oauth.refresh(chosen.oauth, stored)
    assert.equal("original", refreshed.refresh)
    assert.equal("new-opaque", refreshed.access)
    assert.is_true(refreshed.expires_at > oauth.now() + 1400)
end)

it("uses the API endpoint and API key after replacing a ChatGPT sign-in", function()
    local chosen = provider(function(request)
        assert.equal("/responses", request.path)
        assert.equal("Bearer api-key", request.headers.authorization)
        assert.is_nil(request.headers["chatgpt-account-id"])
        assert.is_true(request.body.max_output_tokens > 0)
        assert.equal("system", request.body.input[1].role)
        return Server.events({
            { type = "response.output_text.delta", delta = "API response" },
            { type = "response.completed", response = {} },
        })
    end)
    assert(auth.credentials():save(ID, { type = "oauth", access = "access", refresh = "refresh", account_id = "account", expires_at = 0 }))
    assert(uji.auth.save_key(ID, "api-key"))
    uji.model.use({ provider = chosen.id, model = "gpt-5.5" })
    local answer, failure = model.generate({ system = "test", messages = { { type = "user", text = "hi" } } })
    assert.is_nil(failure)
    assert.equal("API response", answer.text)
    assert.equal("https://chatgpt.com/backend-api/codex/responses", catalog.get("openai").api:url({ auth = { oauth = {} } }))
end)

it("streams ChatGPT tool calls and replays reasoning with the tool result", function()
    local rounds = 0
    provider(function(request)
        assert.equal("/codex/responses", request.path)
        assert.equal("Bearer access", request.headers.authorization)
        assert.equal("chatgpt-account", request.headers["chatgpt-account-id"])
        assert.equal("read_file", request.body.tools[1].name)
        assert.same({ "reasoning.encrypted_content" }, request.body.include)
        rounds = rounds + 1
        if rounds == 1 then
            return Server.events({
                { type = "response.reasoning_summary_text.delta", delta = "Reading." },
                { type = "response.output_item.done", item = { id = "rs_1", type = "reasoning", encrypted_content = "encrypted" } },
                {
                    type = "response.output_item.added",
                    output_index = 1,
                    item = { id = "fc_1", type = "function_call", call_id = "call_1", name = "read_file", arguments = "" },
                },
                { type = "response.function_call_arguments.delta", output_index = 1, delta = '{"path":"test.txt"}' },
                { type = "response.output_item.done", item = { id = "fc_1", type = "function_call" } },
                { type = "response.completed", response = {} },
            })
        end
        assert.equal("encrypted", request.body.input[2].encrypted_content)
        assert.equal("call_1", request.body.input[3].call_id)
        assert.equal("function_call_output", request.body.input[4].type)
        assert.equal("contents", request.body.input[4].output)
        return Server.events({
            { type = "response.output_text.delta", delta = "Read the file." },
            { type = "response.completed", response = {} },
        })
    end)
    assert(
        auth.credentials()
            :save(ID, { type = "oauth", access = "access", refresh = "refresh", account_id = "chatgpt-account", expires_at = 0 })
    )
    uji.model.use({ provider = ID, model = "gpt-5.5" })
    local request = {
        messages = { { type = "user", text = "Read test.txt" } },
        tools = {
            { name = "read_file", description = "Read", parameters = { type = "object", properties = { path = { type = "string" } } } },
        },
        reasoning = true,
        effort = "low",
        max_output = 1024,
    }
    local answer, failure = model.stream(request)
    assert.is_nil(failure)
    assert.equal("Reading.", answer.reasoning)
    assert.equal("call_1", answer.tool_calls[1].id)
    assert.equal('{"path":"test.txt"}', answer.tool_calls[1].arguments)
    request.messages[#request.messages + 1] = {
        type = "assistant",
        text = answer.text,
        tool_calls = answer.tool_calls,
        replay = answer.replay,
    }
    request.messages[#request.messages + 1] = { type = "tool", tool_call_id = "call_1", content = "contents" }
    answer, failure = model.stream(request)
    assert.is_nil(failure)
    assert.equal("Read the file.", answer.text)
    assert.equal(2, rounds)
end)

it("only advertises device login for providers with device settings", function()
    assert.is_true(uji.provider.get("openai").device_auth)
    assert.is_false(uji.provider.get("anthropic").device_auth)
    local ok, err = uji.auth.login("anthropic", { method = "device" })
    assert.is_nil(ok)
    assert.equal("this provider does not support device code sign-in", err)
    assert.is_false(pcall(uji.auth.login, "openai", { method = "unknown" }))
    assert.is_false(pcall(uji.auth.login, "openai", { unknown = true }))
end)

it("offers device login in the command and switches providers only after success", function()
    local choices = { "OpenAI", "Sign in again", "Subscription (sign in with device code)" }
    local offered, configured, success = nil, false, false
    uji.auth.authenticated = function()
        return true
    end
    uji.ui.select = function(opts)
        offered = opts.items
        return table.remove(choices, 1)
    end
    uji.auth.login = function(id, opts)
        assert.equal("openai", id)
        assert.equal("device", opts.method)
        assert.is_false(configured)
        return success or nil, success and nil or "denied"
    end
    uji.model.use = function()
        configured = true
    end
    command.run("login")
    assert.same({ "Subscription (sign in with browser)", "Subscription (sign in with device code)", "API key" }, offered)
    assert.is_false(configured)
    choices = { "OpenAI", "Sign in again", "Subscription (sign in with device code)" }
    success = true
    command.run("login")
    assert.is_true(configured)
end)

it("signs in to Copilot, loads chat models and refreshes its token for requests", function()
    local chosen = catalog.get("github-copilot")
    local polls, tokens = 0, 0
    local server
    server = Server.start(function(request)
        assert.equal("application/json", request.headers.accept)
        if request.path == "/device" then
            assert.equal(chosen.oauth.client_id, request.body.client_id)
            return json({
                device_code = "private-device",
                user_code = "ABCD-1234",
                verification_uri = "https://github.com/login/device",
                interval = 0.01,
                expires_in = 60,
            })
        elseif request.path == "/poll" then
            assert.same({
                client_id = chosen.oauth.client_id,
                device_code = "private-device",
                grant_type = "urn:ietf:params:oauth:grant-type:device_code",
            }, request.body)
            polls = polls + 1
            return json(polls == 1 and { error = "authorization_pending" } or { access_token = "github-token" })
        elseif request.path == "/token" then
            assert.equal("Bearer github-token", request.headers.authorization)
            tokens = tokens + 1
            return json({
                token = "copilot-token-" .. tokens,
                expires_at = oauth.now() + 3600,
                endpoints = { api = server.url .. "/copilot" },
            })
        elseif request.path == "/copilot/models" then
            assert.equal("Bearer copilot-token-1", request.headers.authorization)
            return json({
                data = {
                    {
                        id = "chat-model",
                        capabilities = {
                            type = "chat",
                            supports = { tool_calls = true, vision = true },
                            limits = { max_context_window_tokens = 128000, max_output_tokens = 16384 },
                        },
                        supported_endpoints = { "/chat/completions" },
                    },
                    {
                        id = "responses-only",
                        capabilities = { type = "chat", supports = { tool_calls = true } },
                        supported_endpoints = { "/responses" },
                    },
                    {
                        id = "messages-only",
                        capabilities = { type = "chat", supports = { tool_calls = true } },
                        supported_endpoints = { "/v1/messages" },
                    },
                    { id = "embedding", capabilities = { type = "embeddings" } },
                },
            })
        elseif request.path == "/copilot/responses" then
            assert.equal("responses-only", request.body.model)
            assert.equal("user", request.body.input[1].role)
            return Server.events({
                { type = "response.output_text.delta", delta = "Responses reply" },
                { type = "response.completed", response = { usage = { input_tokens = 2, output_tokens = 1 } } },
            })
        elseif request.path == "/copilot/v1/messages" then
            assert.equal("messages-only", request.body.model)
            assert.equal("2023-06-01", request.headers["anthropic-version"])
            assert.is_nil(request.headers["x-api-key"])
            return Server.events({
                { type = "content_block_delta", index = 0, delta = { type = "text_delta", text = "Messages reply" } },
                { type = "message_delta", delta = { stop_reason = "end_turn" }, usage = { output_tokens = 1 } },
                { type = "message_stop" },
            })
        end
        assert.equal("/copilot/chat/completions", request.path)
        assert.equal("Bearer copilot-token-2", request.headers.authorization)
        assert.equal("vscode-chat", request.headers["copilot-integration-id"])
        assert.equal("user", request.headers["x-initiator"])
        assert.equal("chat-model", request.body.model)
        assert.is_nil(request.body.max_tokens)
        assert.truthy(request.body.max_completion_tokens)
        return Server.text("Hello from Copilot")
    end)
    chosen.base_url = server.url
    chosen.oauth.token_url = server.url .. "/token"
    chosen.oauth.device.code_url = server.url .. "/device"
    chosen.oauth.device.poll_url = server.url .. "/poll"
    process.open = function()
        error("Copilot sign-in must not open a browser")
    end
    local ok, err = uji.auth.login(chosen.id)
    assert.is_nil(err)
    assert.is_true(ok)
    assert.equal(2, polls)
    local loaded = uji.provider.load(chosen.id)
    assert.equal(catalog.STATE.LOADED, loaded.state)
    assert.same({
        { id = "chat-model", context = 128000, output = 16384, images = true, reasoning = false, cache = false },
        { id = "responses-only", images = false, reasoning = false, cache = false },
        { id = "messages-only", images = false, reasoning = false, cache = false },
    }, loaded.models)
    local stored = auth.credentials():get(chosen.id)
    assert.equal("github-token", stored.refresh)
    stored.expires_at = oauth.now() - 1
    assert.truthy(auth.credentials():save(chosen.id, stored))
    uji.model.use({ provider = chosen.id, model = "chat-model" })
    local answer, failure = model.generate({ messages = { { type = "user", text = "hi" } } })
    assert.is_nil(failure)
    assert.equal("Hello from Copilot", answer.text)
    assert.equal(2, tokens)
    assert.equal("copilot-token-2", auth.credentials():get(chosen.id).access)
    for _, entry in ipairs({ { "responses-only", "Responses reply" }, { "messages-only", "Messages reply" } }) do
        uji.model.use({ provider = chosen.id, model = entry[1] })
        local result, failed = model.generate({ messages = { { type = "user", text = "hi" } } })
        assert.is_nil(failed)
        assert.equal(entry[2], result.text)
    end
end)

it("starts Copilot device sign-in without a method picker and keeps the account actions", function()
    local choices = { "GitHub Copilot" }
    local offered, configured, signed_in
    uji.auth.authenticated = function()
        return signed_in == true
    end
    uji.ui.select = function(opts)
        offered = opts.title
        assert.is_not_nil(choices[1], "no extra sign-in method picker")
        return table.remove(choices, 1)
    end
    uji.auth.login = function(id, opts)
        assert.equal("github-copilot", id)
        assert.equal("device", opts.method)
        return true
    end
    uji.model.use = function(opts)
        configured = opts.provider
    end
    command.run("login")
    assert.equal("Provider", offered)
    assert.equal("github-copilot", configured)
    signed_in, configured = true, nil
    choices = { "GitHub Copilot", "Sign in again" }
    command.run("login")
    assert.equal("GitHub Copilot", offered)
    assert.equal("github-copilot", configured)
end)

it("backs off Copilot polling and stops on denied authorization without saving", function()
    local copilot = require("uji.core.auth.copilot")
    local chosen = catalog.get("github-copilot")
    local polls, delays = 0, {}
    copilot.request = function(url, body)
        assert.equal(chosen.oauth.device.poll_url, url)
        assert.equal("private-device", body.device_code)
        polls = polls + 1
        return polls == 1 and { error = "slow_down", interval = 10 } or { error = "access_denied" }
    end
    sys.sleep = function(seconds)
        delays[#delays + 1] = seconds
    end
    local ok, err = pcall(copilot.login, chosen.oauth, {
        id = "private-device",
        interval = 1,
        expires_at = sys.os.clock() + 60,
    })
    assert.is_false(ok)
    assert.truthy(err:find("access_denied", 1, true))
    assert.same({ 1, 10 }, delays)
    assert.is_nil(auth.credentials():get(chosen.id))
end)

it("rejects unsupported Copilot browser login and invalid or refused tokens", function()
    local chosen = catalog.get("github-copilot")
    local ok, err = uji.auth.login(chosen.id, { method = "browser" })
    assert.is_nil(ok)
    assert.equal("this provider does not support browser sign-in", err)
    local response = json({ token = "", expires_at = oauth.now() + 3600 })
    local server = Server.start(function()
        return response
    end)
    chosen.oauth.token_url = server.url
    assert.truthy(auth.credentials():save(chosen.id, {
        type = "oauth",
        access = "expired",
        refresh = "github-token",
        expires_at = 1,
    }))
    for _, reply in ipairs({ response, Server.status(403, "no subscription") }) do
        response = reply
        local credentials, failure = auth.resolve(chosen)
        assert.is_nil(credentials)
        assert.equal("provider", failure.kind)
        assert.equal("expired", auth.credentials():get(chosen.id).access)
    end
end)
