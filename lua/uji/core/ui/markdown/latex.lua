local class = require("uji.core.class")

local CHARACTER = "[%z\1-\127\194-\244][\128-\191]*"

local SYMBOLS = {
    alpha = "α",
    beta = "β",
    gamma = "γ",
    delta = "δ",
    epsilon = "ε",
    varepsilon = "ε",
    zeta = "ζ",
    eta = "η",
    theta = "θ",
    vartheta = "ϑ",
    iota = "ι",
    kappa = "κ",
    lambda = "λ",
    mu = "μ",
    nu = "ν",
    xi = "ξ",
    pi = "π",
    rho = "ρ",
    sigma = "σ",
    tau = "τ",
    upsilon = "υ",
    phi = "φ",
    varphi = "φ",
    chi = "χ",
    psi = "ψ",
    omega = "ω",
    Gamma = "Γ",
    Delta = "Δ",
    Theta = "Θ",
    Lambda = "Λ",
    Xi = "Ξ",
    Pi = "Π",
    Sigma = "Σ",
    Phi = "Φ",
    Psi = "Ψ",
    Omega = "Ω",
    times = "×",
    cdot = "·",
    div = "÷",
    pm = "±",
    mp = "∓",
    ast = "∗",
    star = "⋆",
    circ = "∘",
    bullet = "•",
    oplus = "⊕",
    otimes = "⊗",
    leq = "≤",
    le = "≤",
    geq = "≥",
    ge = "≥",
    neq = "≠",
    ne = "≠",
    approx = "≈",
    equiv = "≡",
    sim = "∼",
    simeq = "≃",
    cong = "≅",
    propto = "∝",
    ll = "≪",
    gg = "≫",
    infty = "∞",
    partial = "∂",
    nabla = "∇",
    sum = "∑",
    prod = "∏",
    int = "∫",
    iint = "∬",
    oint = "∮",
    ["in"] = "∈",
    notin = "∉",
    ni = "∋",
    subset = "⊂",
    subseteq = "⊆",
    supset = "⊃",
    supseteq = "⊇",
    cup = "∪",
    cap = "∩",
    setminus = "∖",
    emptyset = "∅",
    varnothing = "∅",
    forall = "∀",
    exists = "∃",
    neg = "¬",
    lnot = "¬",
    land = "∧",
    wedge = "∧",
    lor = "∨",
    vee = "∨",
    top = "⊤",
    bot = "⊥",
    perp = "⊥",
    parallel = "∥",
    angle = "∠",
    to = "→",
    rightarrow = "→",
    leftarrow = "←",
    gets = "←",
    Rightarrow = "⇒",
    implies = "⇒",
    Leftarrow = "⇐",
    leftrightarrow = "↔",
    Leftrightarrow = "⇔",
    iff = "⇔",
    mapsto = "↦",
    uparrow = "↑",
    downarrow = "↓",
    ldots = "…",
    dots = "…",
    cdots = "⋯",
    vdots = "⋮",
    ddots = "⋱",
    prime = "′",
    ell = "ℓ",
    hbar = "ℏ",
    Re = "ℜ",
    Im = "ℑ",
    aleph = "ℵ",
    mid = "∣",
    vert = "|",
    Vert = "‖",
    langle = "⟨",
    rangle = "⟩",
    lceil = "⌈",
    rceil = "⌉",
    lfloor = "⌊",
    rfloor = "⌋",
    lbrace = "{",
    rbrace = "}",
    quad = "  ",
    qquad = "    ",
    [","] = " ",
    [";"] = " ",
    [":"] = " ",
    [" "] = " ",
    ["!"] = "",
    ["\\"] = "\n",
    ["|"] = "‖",
}

local SILENT = {
    left = true,
    right = true,
    big = true,
    Big = true,
    bigg = true,
    Bigg = true,
    displaystyle = true,
    limits = true,
    nolimits = true,
}

local STYLES = {
    text = true,
    textrm = true,
    textbf = true,
    textit = true,
    mathrm = true,
    mathbf = true,
    mathit = true,
    mathsf = true,
    mathtt = true,
    mathcal = true,
    operatorname = true,
    boldsymbol = true,
    bm = true,
}

local ACCENTS = {
    hat = "\204\130",
    widehat = "\204\130",
    bar = "\204\132",
    overline = "\204\133",
    tilde = "\204\131",
    widetilde = "\204\131",
    dot = "\204\135",
    ddot = "\204\136",
    vec = "\226\131\151",
}

local BLACKBOARD = { N = "ℕ", Z = "ℤ", Q = "ℚ", R = "ℝ", C = "ℂ", P = "ℙ", E = "𝔼" }

local SUPERSCRIPTS = {
    ["0"] = "⁰",
    ["1"] = "¹",
    ["2"] = "²",
    ["3"] = "³",
    ["4"] = "⁴",
    ["5"] = "⁵",
    ["6"] = "⁶",
    ["7"] = "⁷",
    ["8"] = "⁸",
    ["9"] = "⁹",
    ["+"] = "⁺",
    ["-"] = "⁻",
    ["="] = "⁼",
    ["("] = "⁽",
    [")"] = "⁾",
    a = "ᵃ",
    b = "ᵇ",
    c = "ᶜ",
    d = "ᵈ",
    e = "ᵉ",
    f = "ᶠ",
    g = "ᵍ",
    h = "ʰ",
    i = "ⁱ",
    j = "ʲ",
    k = "ᵏ",
    l = "ˡ",
    m = "ᵐ",
    n = "ⁿ",
    o = "ᵒ",
    p = "ᵖ",
    r = "ʳ",
    s = "ˢ",
    t = "ᵗ",
    u = "ᵘ",
    v = "ᵛ",
    w = "ʷ",
    x = "ˣ",
    y = "ʸ",
    z = "ᶻ",
    T = "ᵀ",
    ["⊤"] = "ᵀ",
    ["′"] = "′",
    ["*"] = "*",
    ["∗"] = "*",
}

local SUBSCRIPTS = {
    ["0"] = "₀",
    ["1"] = "₁",
    ["2"] = "₂",
    ["3"] = "₃",
    ["4"] = "₄",
    ["5"] = "₅",
    ["6"] = "₆",
    ["7"] = "₇",
    ["8"] = "₈",
    ["9"] = "₉",
    ["+"] = "₊",
    ["-"] = "₋",
    ["="] = "₌",
    ["("] = "₍",
    [")"] = "₎",
    a = "ₐ",
    e = "ₑ",
    h = "ₕ",
    i = "ᵢ",
    j = "ⱼ",
    k = "ₖ",
    l = "ₗ",
    m = "ₘ",
    n = "ₙ",
    o = "ₒ",
    p = "ₚ",
    r = "ᵣ",
    s = "ₛ",
    t = "ₜ",
    u = "ᵤ",
    v = "ᵥ",
    x = "ₓ",
}

local function atom(value)
    if value:find("[%s%+%-%*/=<>,]") then
        return "(" .. value .. ")"
    end
    return value
end

local function script(value, map, mark)
    local out = {}
    for character in value:gmatch(CHARACTER) do
        local small = map[character]
        if not small then
            return mark .. (value:match("^" .. CHARACTER .. "$") and value or "(" .. value .. ")")
        end
        out[#out + 1] = small
    end
    return table.concat(out)
end

local Reader = class()

function Reader:init(source)
    self.source = source
    self.at = 1
end

function Reader:peek()
    return self.source:sub(self.at, self.at)
end

function Reader:skip_spaces()
    self.at = self.source:find("[^%s]", self.at) or #self.source + 1
end

function Reader:name()
    local name = self.source:match("^%a+", self.at) or self.source:sub(self.at, self.at)
    self.at = self.at + #name
    return name
end

function Reader:group(stop)
    local out = {}
    while self.at <= #self.source do
        if self:peek() == stop then
            self.at = self.at + 1
            break
        end
        out[#out + 1] = self:token()
    end
    return table.concat(out)
end

function Reader:argument()
    self:skip_spaces()
    return self:token()
end

function Reader:command(name)
    if STYLES[name] then
        return self:argument()
    elseif ACCENTS[name] then
        local base = self:argument()
        return base:match("^" .. CHARACTER .. "$") and base .. ACCENTS[name] or base
    elseif name == "mathbb" then
        return (self:argument():gsub(CHARACTER, BLACKBOARD))
    elseif name == "frac" or name == "dfrac" or name == "tfrac" or name == "cfrac" then
        local top = self:argument()
        return atom(top) .. "/" .. atom(self:argument())
    elseif name == "binom" then
        local top = self:argument()
        return "(" .. top .. " choose " .. self:argument() .. ")"
    elseif name == "sqrt" then
        local degree = ""
        if self:peek() == "[" then
            self.at = self.at + 1
            degree = script(self:group("]"), SUPERSCRIPTS, "")
        end
        return degree .. "√" .. atom(self:argument())
    elseif name == "begin" or name == "end" then
        self:argument()
        return ""
    elseif SILENT[name] then
        if self:peek() == "." then
            self.at = self.at + 1
        end
        return ""
    end
    return SYMBOLS[name] or name
end

function Reader:token()
    local char = self:peek()
    self.at = self.at + 1
    if char == "" then
        return ""
    elseif char == "\\" then
        return self:command(self:name())
    elseif char == "{" then
        return self:group("}")
    elseif char == "}" then
        return ""
    elseif char == "^" then
        return script(self:argument(), SUPERSCRIPTS, "^")
    elseif char == "_" then
        return script(self:argument(), SUBSCRIPTS, "_")
    elseif char == "&" or char == "~" or char == "\n" then
        return " "
    end
    self.at = self.at - 1
    local character = self.source:match("^" .. CHARACTER, self.at)
    self.at = self.at + #character
    return character
end

local M = {}

function M.render(source)
    local lines = {}
    for line in (Reader(source):group(nil) .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("%s+", " "):match("^%s*(.-)%s*$")
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, "\n")
end

return M
