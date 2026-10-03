local sandbox = require("support.sandbox")
local sys = require("uji.sys")

it("requires a native module like a Lua module", { native = { "testmod" } }, function()
    local module = require("testmod")
    assert.equal(42, module.add(40, 2))
    assert.equal("hello uji", module.greet("uji"))
    local ok, err = pcall(module.insist, "not today")
    assert.is_false(ok, "a Rust error becomes a Lua error")
    assert.truthy(tostring(err):find("not today", 1, true))
    assert.is_false((pcall(module.add, "forty", 2)), "an argument of the wrong type raises an error")
end)

it("gives a native object fields and methods and lets Lua free it", { native = { "testmod" } }, function()
    local module = require("testmod")
    local before = module.dropped()
    local function hold()
        local counter = module.counter(10, 5)
        assert.equal(10, counter.start)
        assert.equal(15, counter:bump())
        assert.equal(20, counter:bump())
        assert.equal(0, module.dropped() - before, "the object lives while Lua holds it")
    end
    hold()
    collectgarbage()
    collectgarbage()
    assert.equal(1, module.dropped() - before, "the object is dropped in Rust after Lua collects it")
end)

it("replaces a built in module with one found first", {
    native = { "uji/sys/sha256" },
    config = { ["lua/uji/sys/lossy.lua"] = "return function(data) return 'lua ' .. data end" },
}, function()
    assert.equal("replaced abc", sys.sha256("abc"), "a native library replaces it")
    assert.equal("lua abc", sys.lossy("abc"), "a Lua file replaces it")
    assert.equal("YWJj", uji.base64.encode("abc"), "the rest stay built in")
end)

it("uses a module written while uji runs after a reload", function()
    local app = require("uji.core.app")
    local before = sandbox.work .. "/before.json"
    if not sys.os.carry then
        assert.is_true(app.session.pending)
        assert.equal(0, #app.store:sessions())
        app.session:rename("unsaved title")
        sandbox.write(before, sys.json.encode({ lossy = sys.lossy("abc"), session = app.session.id }))
        sandbox.write(sandbox.cfg .. "/lua/uji/sys/lossy.lua", "return function(data) return 'reloaded ' .. data end")
        require("uji.core.config").reload()
        return
    end
    local earlier = sys.json.decode(sandbox.read(before))
    assert.is_true(app.session.pending)
    assert.equal("unsaved title", app.session.title)
    assert.equal(0, #app.store.db:query("SELECT id FROM sessions"))
    assert.equal("abc", earlier.lossy, "the built-in module ran before the reload")
    assert.equal("reloaded abc", sys.lossy("abc"), "the file written while uji ran replaced it")
    assert.equal(earlier.session, app.session.id, "the reload kept the session")
end)
