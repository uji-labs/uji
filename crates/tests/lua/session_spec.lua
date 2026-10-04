local app = require("uji.core.app")
local sandbox = require("support.sandbox")
local Store = require("uji.core.store")
local sys = require("uji.sys")

local ELSEWHERE = "/elsewhere"
local UNKNOWN = "00000000-0000-0000-0000-000000000000"

local function sessions()
    local store = Store(sandbox.work .. "/session-api.db")
    local root = store:create_session("first")
    local child = store:create_session("child", root.id)
    local other = store:create_session("other")
    store.db:exec("UPDATE sessions SET directory = ? WHERE id = ?", { ELSEWHERE, other.id })
    app.store = store
    app.session = child
    return root, child, other
end

local function ids(rows)
    local out = {}
    for _, row in ipairs(rows) do
        out[row.id] = row
    end
    return out
end

it("lists the stored sessions without the ones saved under another", function()
    local root, child, other = sessions()
    local listed = ids(uji.session.list())
    assert.equal("first", listed[root.id].title)
    assert.equal("other", listed[other.id].title)
    assert.is_nil(listed[child.id])
    assert.equal("number", type(listed[root.id].updated))
end)

it("lists only the sessions of one directory", function()
    local root, _, other = sessions()
    local here = ids(uji.session.list({ directory = sys.os.cwd() }))
    assert.truthy(here[root.id])
    assert.is_nil(here[other.id])
    local there = uji.session.list({ directory = ELSEWHERE })
    assert.equal(1, #there)
    assert.equal(other.id, there[1].id)
    assert.has_error(function()
        uji.session.list({ directory = 1 })
    end)
end)

it("refuses to delete the open session or a session it is saved under", function()
    local root, child = sessions()
    assert.same({ nil, "the open session cannot be deleted" }, { uji.session.delete(child.id) })
    assert.same({ nil, "deleting it would delete the open session too" }, { uji.session.delete(root.id) })
    assert.truthy(app.store:session(root.id))
end)

it("deletes a session and explains an id it cannot delete", function()
    local _, _, other = sessions()
    assert.is_true(uji.session.delete(other.id))
    assert.is_nil(app.store:session(other.id))
    assert.same({ nil, "no session with id " .. UNKNOWN }, { uji.session.delete(UNKNOWN) })
    assert.same({ nil, "invalid session id: not-an-id" }, { uji.session.delete("not-an-id") })
    assert.has_error(function()
        uji.session.delete(nil)
    end)
end)
