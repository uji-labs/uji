local common = require("uji.builtin.apis.common")
local stream = require("uji.builtin.apis.stream")

local Jev = uji.class()

Jev.model = "jev-latest"

function Jev:init(opts)
    for key, value in pairs(opts or {}) do
        self[key] = value
    end
end

local function question_map(questions)
    local out = {}
    for id, instructions in pairs(questions) do
        out[id] = { type = "noul", instructions = instructions }
    end
    return out
end

function Jev:decision(request)
    local response, err = uji.net.open({
        url = request.provider.base_url .. "/systemone",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            Authorization = common.bearer(request.auth.key),
        },
        body = uji.json.encode({
            model = request.model ~= "" and request.model or self.model,
            state = request.state,
            questions = question_map(request.questions),
        }),
        timeout = request.timeout,
        idle = request.timeout,
    })
    if not response then
        return nil, { kind = "http", message = err }
    end
    if response.status < 200 or response.status >= 300 then
        return nil, stream.status_error({ status = response.status, headers = response.headers, body = response:read() or "" })
    end
    local ok, body = pcall(uji.json.decode, response:read() or "")
    if not ok or type(body) ~= "table" or type(body.answers) ~= "table" then
        return nil, { kind = "provider", message = "Jev's answer had no answers" }
    end
    return body.answers
end

return Jev
