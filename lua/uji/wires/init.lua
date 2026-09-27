local wire = require("uji.wire")

wire.add("openai-chat", require("uji.wires.openai_chat"))
wire.add("anthropic", require("uji.wires.anthropic"))
wire.add("gemini", require("uji.wires.gemini"))
