local highlight = require("uji.core.ui.markdown.highlight")
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

it("highlights a known language and skips an unknown one", function()
    local styles = { plain = "text", keyword = "keyword", string = "literal", number = "literal", comment = "comment" }
    local python = highlight.new("python title=x", styles)
    assert.same({
        { "def", "keyword" },
        { " f(x): ", "text" },
        { "return", "keyword" },
        { " ", "text" },
        { '"a"', "literal" },
        { " ", "text" },
        { "# b", "comment" },
    }, python:line('def f(x): return "a" # b'))
    assert.same({ { '"""doc', "literal" } }, python:line('"""doc'))
    assert.same({ { 'string"""', "literal" }, { " ", "text" }, { "1", "literal" } }, python:line('string""" 1'))
    assert.is_nil(highlight.new("brainfuck", styles))
    assert.is_nil(highlight.new(nil, styles))
end)
