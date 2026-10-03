stds.luajit52 = {
    read_globals = {
        package = { fields = { "searchers" } },
        table = { fields = { "unpack" } },
    },
}

std = "luajit+luajit52"
globals = { "uji" }
self = false
max_line_length = false
exclude_files = { "crates/tests/lua/vendor" }

files["crates/tests/lua/*_spec.lua"] = {
    read_globals = {
        "after_each",
        "before_each",
        "describe",
        "it",
        assert = { other_fields = true },
        match = { other_fields = true },
        spy = { other_fields = true },
    },
}
