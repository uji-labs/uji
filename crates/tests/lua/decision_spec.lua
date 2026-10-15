local server = require("support.server")
local sys = require("uji.sys")

local Jev = require("uji.builtin.apis.jev")

local function answers(probabilities)
    return sys.json.encode({ answers = probabilities })
end

local function chatty(url)
    uji.provider.add({
        id = "chatty",
        name = "Chatty",
        api = uji.api.openai(),
        base_url = url .. "/v1",
        models = { { id = "m", context = 100000, output = 1000 } },
    })
    uji.model.use({ provider = "chatty", model = "m" })
end

local function judge(url)
    uji.provider.add({
        id = "jev-test",
        name = "Jev Test",
        api = Jev(),
        base_url = url .. "/v1",
        auth_env = { "TYPESAFE_API_KEY" },
        models = {},
    })
    uji.auth.save_key("jev-test", "secret")
end

describe("decisions", function()
    it("ships a provider that answers decisions and no chat", function()
        local row = uji.provider.get("jev")
        assert.equal("Jev", row.name)
        assert.equal("https://api.typesafe.ai/v1", row.base_url)
        assert.equal("function", type(row.api.decision))
        assert.is_nil(row.api.stream)
    end)

    it("asks the provider in use over chat and calls the answer an estimate", function()
        local mock = server.start(function()
            return server.text(answers({ safe = { noul = 0.91 }, ["2"] = { noul = 0.4 } }))
        end)
        chatty(mock.url)
        local found = uji.model.decide({
            state = "a coding agent working in /work wants to run `ls`",
            questions = { safe = "Is this safe to run unattended?" },
            timeout = 10,
        })
        assert.is_not_nil(found)
        assert.equal(0.91, found.probabilities.safe)
        assert.is_false(found.calibrated)

        local asked = mock.requests[1].raw
        assert.truthy(asked:find("Is this safe to run unattended?", 1, true))
        assert.truthy(asked:find("certainly yes", 1, true))
        assert.truthy(asked:find("run `ls`", 1, true))
    end)

    it("asks every question in one request, in order, from a state in parts", function()
        local mock = server.start(function()
            return server.text(answers({ safe = { noul = 0.6 }, ["2"] = { noul = 0.9 } }))
        end)
        chatty(mock.url)
        local found = uji.model.decide({
            state = { "a coding agent wants to run `ls`", "the user asked for a listing" },
            questions = { ["2"] = "Is line 2 safe?", safe = "Is this safe?" },
            timeout = 10,
        })
        assert.is_not_nil(found)
        assert.equal(0.6, found.probabilities.safe)
        assert.equal(0.9, found.probabilities["2"])

        local asked = mock.requests[1].raw
        assert.truthy(asked:find("the user asked for a listing", 1, true))
        local numbered = asked:find("2: Is line 2 safe?", 1, true)
        local named = asked:find("safe: Is this safe?", 1, true)
        assert.is_true(numbered ~= nil and named ~= nil and numbered < named, "the questions were not listed in order")
    end)

    it("asks a provider with a decision method itself and calls the answer calibrated", function()
        local seen
        local mock = server.start(function(request)
            seen = request
            return server.status(200, answers({ safe = { noul = 0.97 }, ["2"] = { noul = 0.2 } }))
        end)
        judge(mock.url)
        local found = uji.model.decide({
            provider = "jev-test",
            state = "a coding agent wants to run `rm -rf build`",
            questions = { safe = "Is this safe?", ["2"] = "Is line 2 safe?" },
            timeout = 10,
        })
        assert.is_not_nil(found)
        assert.equal(0.97, found.probabilities.safe)
        assert.equal(0.2, found.probabilities["2"])
        assert.is_true(found.calibrated)

        local body = seen.body
        assert.equal("jev-latest", body.model)
        assert.equal("noul", body.questions.safe.type)
        assert.equal("Is line 2 safe?", body.questions["2"].instructions)
        assert.truthy(seen.path:find("/systemone", 1, true))
    end)

    it("answers with the model named and the ones the api leaves out", function()
        local seen
        local mock = server.start(function(request)
            seen = request
            return server.status(200, answers({ safe = { noul = 0.5 } }))
        end)
        judge(mock.url)
        local found = uji.model.decide({
            provider = "jev-test",
            model = "jev-2",
            state = "state",
            questions = { safe = "Is this safe?", ["2"] = "Is line 2 safe?" },
        })
        assert.equal(0.5, found.probabilities.safe)
        assert.is_nil(found.probabilities["2"])
        assert.equal("jev-2", seen.body.model)
    end)

    it("leaves out a probability that is not one, so the question is asked instead", function()
        local mock = server.start(function()
            return server.status(200, answers({ safe = { noul = 95 }, ["2"] = { noul = 0.4 } }))
        end)
        judge(mock.url)
        local found = uji.model.decide({
            provider = "jev-test",
            state = "state",
            questions = { safe = "Is this safe?", ["2"] = "Is line 2 safe?" },
        })
        assert.is_not_nil(found)
        assert.is_nil(found.probabilities.safe)
        assert.equal(0.4, found.probabilities["2"])
    end)

    it("says what to set when there is no key", function()
        uji.provider.add({
            id = "jev-nokey",
            name = "Jev Nokey",
            api = Jev(),
            base_url = "http://127.0.0.1:1/v1",
            auth_env = { "UJI_TEST_UNSET_KEY" },
            models = {},
        })
        local found, failure = uji.model.decide({
            provider = "jev-nokey",
            state = "state",
            questions = { safe = "Is this safe?" },
        })
        assert.is_nil(found)
        assert.equal("auth", failure.kind)
        assert.truthy(failure.message:find("UJI_TEST_UNSET_KEY", 1, true))
    end)

    it("reports a provider that cannot answer, and one that failed", function()
        local found, failure = uji.model.decide({
            provider = "openrouter",
            state = "state",
            questions = { safe = "Is this safe?" },
        })
        assert.is_nil(found)
        assert.equal("provider", failure.kind)
        assert.truthy(failure.message:find("cannot answer a decision", 1, true))

        local mock = server.start(function()
            return server.status(500, "upstream exploded")
        end)
        judge(mock.url)
        local failed, problem = uji.model.decide({
            provider = "jev-test",
            state = "state",
            questions = { safe = "Is this safe?" },
        })
        assert.is_nil(failed)
        assert.equal("http", problem.kind)
        assert.equal(500, problem.status)
        assert.truthy(problem.message:find("upstream exploded", 1, true))
    end)

    it("keeps a failure to answer away from the caller's error", function()
        local mock = server.start(function()
            return server.status(200, '{"answers":')
        end)
        judge(mock.url)
        local found, failure = uji.model.decide({
            provider = "jev-test",
            state = "state",
            questions = { safe = "Is this safe?" },
        })
        assert.is_nil(found)
        assert.equal("provider", failure.kind)
        assert.truthy(failure.message:find("no answers", 1, true))
    end)

    it("refuses a state or a question it cannot read as text", function()
        local ok, failure = pcall(uji.model.decide, { state = 5, questions = { safe = "Is this safe?" } })
        assert.is_false(ok)
        assert.truthy(failure:find("needs state", 1, true))
        assert.truthy(failure:find("list of strings", 1, true))

        ok, failure = pcall(uji.model.decide, { state = "state", questions = { safe = 5 } })
        assert.is_false(ok)
        assert.truthy(failure:find("question safe as a string", 1, true))

        ok, failure = pcall(uji.model.decide, { state = "state", questions = { [1] = "Is this safe?" } })
        assert.is_false(ok)
        assert.truthy(failure:find("with a string, not number", 1, true))

        ok, failure = pcall(uji.model.decide, { state = "state", questions = "nope" })
        assert.is_false(ok)
        assert.truthy(failure:find("needs questions", 1, true))
    end)
end)
