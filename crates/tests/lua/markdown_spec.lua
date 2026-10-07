local latex = require("uji.core.ui.markdown.latex")
local sys = require("uji.sys")

local function maths(source)
    local out = {}
    for _, event in ipairs(sys.markdown(source)) do
        if event[1] == "math" then
            out[#out + 1] = { event[2], event[3], source:sub(event[4], event[5]) }
        end
    end
    return out
end

it("parses dollar and bracket math with offsets into the original text", function()
    assert.same({
        { "x", false, "$x$" },
        { "{y}", false, "\\(y\\)" },
        { "z", true, "$$z$$" },
        { "w", true, "\\[w\\]" },
    }, maths("a $x$ b \\(y\\) c $$z$$ d \\[w\\]"))
end)

it("leaves brackets in code, escaped brackets and prices alone", function()
    assert.same({}, maths("`\\(x\\)` and \\\\(y\\\\) cost $5 or $10\n\n```\n\\[z\\]\n```"))
end)

it("turns TeX into readable text", function()
    assert.equal("a₁ + bₘₐₓ ≤ x⁻¹", latex.render("a_1 + b_{max} \\leq x^{-1}"))
    assert.equal("(a + b)/2 = √(α + β²)", latex.render("\\frac{a + b}{2} = \\sqrt{\\alpha + \\beta^2}"))
    assert.equal("ℝⁿ e^(iπ) x̂", latex.render("\\mathbb{R}^n e^{i\\pi} \\hat{x}"))
    assert.equal("a = b\nc ≤ ∞", latex.render("\\begin{aligned} a &= b \\\\ c &\\leq \\infty \\end{aligned}"))
end)

it("highlights a known language line by line and skips an unknown one", function()
    local function shape(tokens)
        local out = {}
        for index, token in ipairs(tokens) do
            out[index] = { token.text, token.kind }
        end
        return out
    end
    local lines = uji.highlight("python", 'def f(x): return "a" # b\nclass Box:\n    value = True\n"""doc\nstring""" 1')
    assert.same({
        { "def", "keyword" },
        { " ", "plain" },
        { "f", "func" },
        { "(x): ", "plain" },
        { "return", "keyword" },
        { " ", "plain" },
        { '"a"', "string" },
        { " ", "plain" },
        { "# b", "comment" },
    }, shape(lines[1]))
    assert.same({ { "class", "keyword" }, { " ", "plain" }, { "Box", "type" }, { ":", "plain" } }, shape(lines[2]))
    assert.same({ { "    value = ", "plain" }, { "True", "constant" } }, shape(lines[3]))
    assert.same({ { '"""doc', "comment" } }, shape(lines[4]))
    assert.same({ { 'string"""', "comment" }, { " ", "plain" }, { "1", "number" } }, shape(lines[5]))
    assert.equal(1, #uji.highlight("ts", "let value = 1"))
    assert.is_nil(uji.highlight("brainfuck", "+"))
end)
