local sandbox = require("support.sandbox")
local sys = require("uji.sys")

local function raises(fn, ...)
    return not pcall(fn, ...)
end

it("raises on arguments of the wrong type", function()
    assert.is_true(raises(sys.fs.read))
    assert.is_true(raises(sys.base64.encode, {}))
    assert.is_true(raises(sys.sleep, "soon"))
    assert.is_true(raises(sys.sleep, -1))
    assert.is_true(raises(sys.sleep, 0 / 0))
    assert.is_true(raises(sys.task.timeout, -1, function() end))
    assert.is_true(raises(sys.task.race))
    assert.is_true(raises(sys.proc.spawn, "not a list"))
end)

it("gives back nil and a message for an expected failure", function()
    local missing = sandbox.work .. "/missing"
    local function check(label, value, message)
        assert.is_nil(value, label .. " gave a value")
        assert.is_string(message, label .. " gave no message")
        assert.is_true(#message > 0, label .. " gave no message")
    end
    check("read", sys.fs.read(missing))
    check("list", sys.fs.list(missing))
    check("stat", sys.fs.stat(missing))
    check("remove", sys.fs.remove(missing))
    check("rename", sys.fs.rename(missing, missing .. "2"))
    check("spawn", sys.proc.spawn({ "uji-no-such-program" }))
    check("empty argv", sys.proc.spawn({}))
    check("url", sys.net.request({ url = "not a url" }))
    check("method", sys.net.request({ url = "http://127.0.0.1:9", method = "NOT A METHOD" }))
    check("regex", sys.regex("("))
    check("glob", sys.glob("a[b"))
    check("database", sys.db.open(missing .. "/nested/uji.db"))
end)

it("raises on bad input to a codec", function()
    assert.is_true(raises(sys.base64.decode, "@@@"))
    assert.is_true(raises(sys.json.decode, "{"))
    assert.is_true(raises(sys.json.encode, { f = function() end }))
    assert.is_true(raises(sys.toml.decode, "= nope"))
    assert.is_true(raises(sys.toml.encode, "not a table"))
    assert.is_true(raises(sys.markdown))
end)

it("gives an error message without the stack trace", function()
    local _, decoded = pcall(sys.base64.decode, "@@@")
    assert.equal("Invalid symbol 64, offset 0.", sys.message(decoded))
    local _, plain = pcall(error, "plain", 0)
    assert.equal("plain", sys.message(plain))
    local custom = setmetatable({}, {
        __tostring = function()
            return "custom"
        end,
    })
    assert.equal("custom", sys.message(custom))
    assert.equal("bad \239\191\189 byte", sys.message("bad \255 byte"))
    local _, raced = pcall(sys.task.race, function()
        error("from a racer", 0)
    end)
    assert.equal("from a racer", sys.message(raced))
end)

it("reports a failing task and keeps the others running", function()
    local reported = {}
    sys.task.on_error(function(message)
        reported[#reported + 1] = message
    end)
    local survived = false
    sys.task.spawn(function()
        error("task boom", 0)
    end)
    sys.task.spawn(function()
        sys.sleep(0.01)
        survived = true
    end)
    sys.sleep(0.05)
    assert.equal("task boom", reported[1], "the report has no stack trace")
    assert.is_true(survived)
end)

it("raises the original error from race and timeout and stops the rest", function()
    local raced, race_error = pcall(uji.task.race, function()
        error({ code = 7 })
    end, function()
        sys.sleep(1)
    end)
    assert.is_false(raced)
    assert.same({ code = 7 }, race_error)
    local timed, timeout_error = pcall(uji.task.timeout, 1, function()
        error({ code = 8 })
    end)
    assert.is_false(timed)
    assert.same({ code = 8 }, timeout_error)
    local finished = uji.task.timeout(0.01, function()
        sys.sleep(1)
    end)
    assert.is_false(finished, "the timeout ran out")
    local loser = false
    uji.task.race(function()
        return "fast"
    end, function()
        sys.sleep(0.02)
        loser = true
    end)
    sys.sleep(0.05)
    assert.is_false(loser, "the losing racer was stopped")
end)

it("stops a cancelled task where it waits", function()
    local reached = false
    local waiting = sys.task.spawn(function()
        sys.sleep(0.02)
        reached = true
    end)
    waiting:cancel()
    waiting:cancel()
    local done = sys.task.spawn(function() end)
    sys.sleep(0.05)
    done:cancel()
    assert.is_false(reached)
end)

it("settles a promise once and keeps every value", function()
    local promise = sys.promise()
    assert.is_false(promise.settled)
    assert.is_true(promise:resolve(1, nil, 3))
    assert.is_false(promise:resolve("again"))
    assert.is_true(promise.settled)
    local first, second, third = promise:await()
    assert.equal(3, select("#", promise:await()))
    assert.equal(1, first)
    assert.is_nil(second)
    assert.equal(3, third)
    local later = sys.promise()
    local got
    sys.task.spawn(function()
        got = later:await()
    end)
    sys.sleep(0)
    later:resolve("woken")
    sys.sleep(0)
    assert.equal("woken", got)
end)

it("rolls back a failed transaction and raises the original error", function()
    local db = assert(sys.db.open(sandbox.work .. "/failures.db"))
    db:exec("CREATE TABLE items (name TEXT)")
    local function count()
        return #db:query("SELECT name FROM items")
    end
    local ok, err = pcall(db.transaction, db, function()
        db:exec("INSERT INTO items (name) VALUES (?)", { "dropped" })
        error({ code = 9 })
    end)
    assert.is_false(ok)
    assert.same({ code = 9 }, err, "the original table came back")
    assert.equal(0, count(), "nothing was kept")
    local waited = pcall(db.transaction, db, function()
        db:exec("INSERT INTO items (name) VALUES (?)", { "waiting" })
        sys.sleep(0)
    end)
    assert.is_false(waited, "waiting inside a transaction fails")
    assert.equal(0, count(), "waiting inside a transaction rolls back")
    local done, rows = db:transaction(function()
        db:exec("INSERT INTO items (name) VALUES (?)", { "saved" })
        return "done", 2
    end)
    assert.equal("done", done)
    assert.equal(2, rows)
    assert.equal(1, count())
    assert.is_true(raises(db.exec, db, "NOT SQL"), "bad SQL raises")
    assert.is_true(raises(db.exec, db, "INSERT INTO items (name) VALUES (?)", { {} }), "a table cannot be stored")
    db:close()
    assert.is_true(raises(db.query, db, "SELECT 1"), "a closed database raises")
end)

it("draws nothing for screen calls off the screen and raises for bad ones", function()
    local screen = require("ito").open()
    assert.is_true((pcall(screen.fill, screen, { x = -3, y = -3, width = 5, height = 5 })))
    assert.equal(0, screen:line(-1, 0, "x"), "a row above the screen draws nothing")
    assert.equal(-4, screen:line(0, -4, "x"), "the column stays where it was")
    assert.equal(0, screen:line(10000, 0, "x"), "a row below the screen draws nothing")
    assert.is_nil(screen:text(-1))
    assert.is_true((pcall(screen.cursor, screen, -1, 2)))
    assert.is_true(raises(screen.line, screen, 0, 0, 42))
    assert.is_true(raises(screen.line, screen, 0, 0, { 42 }))
    assert.is_true(raises(screen.line, screen, 0, 0, { { "x", { fg = "cyan" } } }))
    assert.is_true(raises(screen.cursor, screen, 0, 0, "wiggle"))
    assert.is_true(raises(screen.paint, screen, { x = 0, y = 0, width = 1, height = 1 }, 9999))
end)

it("says where it looked for a missing module", function()
    local ok, err = pcall(require, "uji-no-such-module")
    assert.is_false(ok)
    assert.truthy(err:find("no runtime module", 1, true))
    assert.truthy(err:find("no built-in module", 1, true))
    assert.is_true(raises(require, "uji.sys.no_such_thing"))
end)

it("still handles text that is not UTF-8", function()
    local bad = "\255\255abc"
    assert.equal(1, sys.width("\255"))
    assert.equal("\239\191\189\239\191\189abc", sys.lossy(bad))
    assert.same({ 3, 5 }, { sys.regex("abc"):find(bad) }, "positions point into the original bytes")
    assert.same({ 1 }, sys.fuzzy("ab", { "\255xab", "zzz" }))
    assert.is_true(#sys.markdown("\255 *text*") > 0)
    assert.equal("//9hYmM=", sys.base64.encode(bad))
    assert.equal('{"text":"\239\191\189\239\191\189abc"}', sys.json.encode({ text = bad }))
end)

it("gives nil for a missing name", function()
    assert.is_nil(uji[nil])
    assert.is_nil(uji[{}])
    assert.is_nil(uji.no_such_name)
    assert.is_nil(sys.no_such_module)
    assert.is_nil(sys.no_such_module)
end)

it("does not finish a wait inside your own coroutine", function()
    local result = coroutine.wrap(function()
        sys.sleep(0.01)
        return "done"
    end)()
    assert.are_not.equal("done", result)
end)

it("runs nothing after exit", function()
    local child = sandbox.dir("child")
    local out = child.root .. "/seen.txt"
    sandbox.write(
        child.cfg .. "/init.lua",
        string.format(
            [[
local sys = require("uji.sys")
local seen = assert(io.open(%q, "w"))
local function emit(text)
    seen:write(text, "\n")
    seen:flush()
end
emit("before")
sys.task.spawn(function()
    emit("other task")
end)
sys.os.exit(0)
sys.sleep(0)
emit("after")
]],
            out
        )
    )
    local process = require("uji.core.system.process")
    local result = process.run({
        argv = {
            sandbox.bin,
            "run",
            "--config-dir",
            child.cfg,
            "--data-dir",
            child.data,
            "--db",
            child.db,
            "hello",
        },
        cwd = child.work,
    }, function() end)
    assert.equal(0, result.code)
    assert.same({ "before" }, sandbox.lines(out))
end)
