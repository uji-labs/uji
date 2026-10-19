local server = require("support.server")
local stream = require("uji.builtin.apis.stream")

local KINDS = { "gzip", "deflate", "zstd", "br" }

local function post(mock, body, encoding)
    local answer, err = uji.net.open({
        url = mock.url .. "/v1/chat/completions",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = body,
        encoding = encoding,
    })
    assert.is_nil(err)
    answer:read()
    return mock.requests[#mock.requests]
end

it("compresses only the provider that decodes it", function()
    assert.equal("gzip", stream.encoding("anthropic"))
    assert.is_nil(stream.encoding("openai"))
    assert.is_nil(stream.encoding("mine"))
    assert.is_nil(stream.encoding(nil))
end)

it("packs a body the way it is told to", function()
    local mock = server.start(function()
        return server.text("ok")
    end)
    local body = '{"model":"m","pad":"' .. string.rep("alpha beta ", 800) .. '"}'
    for _, kind in ipairs(KINDS) do
        local request = post(mock, body, kind)
        assert.equal(kind, request.headers["content-encoding"])
        assert.is_true(#request.raw < #body, "the " .. kind .. " body is smaller")
    end
    local plain = post(mock, body)
    assert.is_nil(plain.headers["content-encoding"])
    assert.equal(body, plain.raw)
end)

it("leaves a body too small to bother with alone", function()
    local mock = server.start(function()
        return server.text("ok")
    end)
    local body = '{"model":"m"}'
    local request = post(mock, body, "gzip")
    assert.is_nil(request.headers["content-encoding"])
    assert.equal(body, request.raw)
end)
